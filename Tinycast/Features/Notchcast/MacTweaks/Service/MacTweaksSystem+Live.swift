// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation
import OSLog

extension MacTweaksSystem {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "MacTweaks")

    enum LiveFailure: Error, Equatable {
        case unsupportedPreference
        case invalidTarget
        case invalidValue
        case invalidProcessOutput
        case refused
        case processFailed(String, Int32)
        case stopped(String)
        case couldNotStart(String)
    }

    static func live() -> Self {
        let session = "gui/\(getuid())"
        return Self(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            journalFolder: AppPaths.applicationSupport().appending(path: "Notchcast/MacTweaks", directoryHint: .isDirectory),
            read: { target in
                try read(target, synchronize: synchronize) { try disabledServices(session: session) }
            },
            readAll: { targets in
                let synchronizeOnce = DomainSync(synchronize)
                var services: Result<Set<String>, any Error>?
                func disabled() throws -> Set<String> {
                    let result = services ?? Result { try disabledServices(session: session) }
                    services = result
                    return try result.get()
                }
                return Dictionary(targets.map { target in
                    (target, Result { try read(target, synchronize: synchronizeOnce.callAsFunction, disabled: disabled) })
                }, uniquingKeysWith: { first, _ in first })
            },
            write: { target, value in
                switch target {
                case .preference(let domain, let key, let appOnly):
                    try writePreference(domain, key: key, appOnly: appOnly, value: value)
                case .service(let label):
                    guard case .bool(let disable)? = value else { throw LiveFailure.invalidValue }
                    try setService(label, disabled: disable, session: session)
                case .libraryHidden:
                    guard case .bool(let hidden)? = value else { throw LiveFailure.invalidValue }
                    var values = URLResourceValues()
                    values.isHidden = hidden
                    var library = FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: "Library", directoryHint: .isDirectory)
                    try library.setResourceValues(values)
                }
            },
            restart: { process in
                try checkedRestart(run("/usr/bin/killall", [process.rawValue]))
            },
            now: { Date() }
        )
    }

    // One synchronize per domain in a pass, and its failure answers every key of that domain.
    final class DomainSync {
        private var results: [String: Result<Void, any Error>] = [:]
        private let body: (String) throws -> Void

        init(_ body: @escaping (String) throws -> Void) {
            self.body = body
        }

        func callAsFunction(_ domain: String) throws {
            let name = isGlobal(domain) ? "NSGlobalDomain" : domain
            let result = results[name] ?? Result { try body(name) }
            results[name] = result
            try result.get()
        }
    }

    private static func isGlobal(_ domain: String) -> Bool {
        domain == "NSGlobalDomain" || domain == ".GlobalPreferences"
    }

    private static func synchronize(_ domain: String) throws {
        let synchronized = isGlobal(domain)
            ? CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            : CFPreferencesAppSynchronize(domain as CFString)
        guard synchronized else { throw LiveFailure.refused }
    }

    private static func read(
        _ target: MacTweakTarget, synchronize: (String) throws -> Void, disabled: () throws -> Set<String>
    ) throws -> Reading {
        switch target {
        case .preference(let domain, let key, let appOnly):
            return try readPreference(domain, key: key, appOnly: appOnly, synchronize: synchronize)
        case .service(let label):
            try validate(label)
            let value = MacTweakValue.bool(try disabled().contains(label))
            return Reading(stored: value, effective: value)
        case .libraryHidden:
            let library = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library", directoryHint: .isDirectory)
            guard let hidden = try library.resourceValues(forKeys: [.isHiddenKey]).isHidden else {
                throw LiveFailure.refused
            }
            let value = MacTweakValue.bool(hidden)
            return Reading(stored: value, effective: value)
        }
    }

    private static func disabledServices(session: String) throws -> Set<String> {
        disabledServices(try run("/bin/launchctl", ["print-disabled", session]).checked())
    }

    private static func readPreference(
        _ domain: String, key: String, appOnly: Bool, synchronize: (String) throws -> Void
    ) throws -> Reading {
        let global = isGlobal(domain)
        let application = global ? kCFPreferencesAnyApplication : domain as CFString
        let name = key as CFString
        try synchronize(domain)
        func copy(_ user: CFString, _ host: CFString, from scope: CFString) -> CFPropertyList? {
            CFPreferencesCopyValue(name, scope, user, host)
        }
        let own = copy(kCFPreferencesCurrentUser, kCFPreferencesAnyHost, from: application)
        if global, let forced = forcedGlobalValue(key) {
            return Reading(stored: nil, effective: try value(forced), managed: true)
        }
        if !global, CFPreferencesAppValueIsForced(name, application) {
            return Reading(stored: nil, effective: try value(CFPreferencesCopyAppValue(name, application)), managed: true)
        }
        let stored = try value(own)
        if let currentHost = copy(kCFPreferencesCurrentUser, kCFPreferencesCurrentHost, from: application) {
            return Reading(stored: stored, effective: try value(currentHost), heldElsewhere: .thisMac)
        }
        if own != nil || appOnly { return Reading(stored: stored, effective: stored) }
        if !global { try synchronize("NSGlobalDomain") }
        let layer = kCFPreferencesAnyApplication
        if !global, let userGlobal = copy(kCFPreferencesCurrentUser, kCFPreferencesCurrentHost, from: layer)
            ?? copy(kCFPreferencesCurrentUser, kCFPreferencesAnyHost, from: layer) {
            return Reading(stored: nil, effective: try value(userGlobal), heldElsewhere: .everyApp)
        }
        if let everyUser = copy(kCFPreferencesAnyUser, kCFPreferencesCurrentHost, from: application)
            ?? copy(kCFPreferencesAnyUser, kCFPreferencesAnyHost, from: application) {
            return Reading(stored: nil, effective: try value(everyUser), heldElsewhere: .everyAccount)
        }
        if !global, let everyUserGlobal = copy(kCFPreferencesAnyUser, kCFPreferencesCurrentHost, from: layer)
            ?? copy(kCFPreferencesAnyUser, kCFPreferencesAnyHost, from: layer) {
            return Reading(stored: nil, effective: try value(everyUserGlobal), heldElsewhere: .everyApp)
        }
        return Reading(stored: nil, effective: nil)
    }

    private static func writePreference(
        _ domain: String, key: String, appOnly: Bool, value: MacTweakValue?
    ) throws {
        guard try readPreference(domain, key: key, appOnly: appOnly, synchronize: synchronize).block == nil
        else { throw LiveFailure.refused }
        let global = isGlobal(domain)
        let application = global ? kCFPreferencesAnyApplication : domain as CFString
        CFPreferencesSetValue(
            key as CFString, value.map(property), application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw LiveFailure.refused
        }
    }

    private static func forcedGlobalValue(_ key: String) -> Any? {
        let folder = "/Library/Managed Preferences"
        for path in ["\(folder)/\(NSUserName())/.GlobalPreferences.plist", "\(folder)/.GlobalPreferences.plist"] {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            do {
                let managed = try PropertyListSerialization.propertyList(from: data, format: nil)
                if let value = (managed as? [String: Any])?[key] { return value }
            } catch {
                logger.error("Could not read managed preferences: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    private static func value(_ object: Any?) throws -> MacTweakValue? {
        guard let object else { return nil }
        return try storedValue(object)
    }

    private static func storedValue(_ object: Any) throws -> MacTweakValue {
        switch object {
        case let string as String: return .string(string)
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return .bool(number.boolValue)
        case let number as NSNumber where CFNumberIsFloatType(number): return .real(number.doubleValue)
        case let number as NSNumber: return .integer(number.int64Value)
        case let data as Data: return .data(data)
        case let date as Date: return .date(date)
        case let array as [Any]: return try .array(array.map(storedValue))
        case let dictionary as [String: Any]: return try .dictionary(dictionary.mapValues(storedValue))
        default: throw LiveFailure.unsupportedPreference
        }
    }

    private static func property(_ value: MacTweakValue) -> CFPropertyList {
        switch value {
        case .bool(let flag): flag as NSNumber
        case .integer(let number): number as NSNumber
        case .real(let number): number as NSNumber
        case .string(let string): string as NSString
        case .data(let data): data as NSData
        case .date(let date): date as NSDate
        case .array(let values): values.map(property) as NSArray
        case .dictionary(let values): values.mapValues(property) as NSDictionary
        }
    }

    private static func validate(_ label: String) throws {
        guard !label.isEmpty, !label.hasPrefix("-"),
              label.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || [45, 46, 95].contains($0) })
        else { throw LiveFailure.invalidTarget }
    }

    private static func disabledServices(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { return nil }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { return nil }
            return parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        })
    }

    private static func setService(_ label: String, disabled: Bool, session: String) throws {
        try validate(label)
        let target = "\(session)/\(label)"
        let launchctl = "/bin/launchctl"
        _ = try run(launchctl, [disabled ? "disable" : "enable", target]).checked()
        let loaded = try run(launchctl, ["print", target]).status == 0
        if disabled, loaded {
            _ = try run(launchctl, ["bootout", target]).checked()
        } else if !disabled, !loaded {
            let plist = "/System/Library/LaunchAgents/\(label).plist"
            if FileManager.default.fileExists(atPath: plist) {
                _ = try run(launchctl, ["bootstrap", session, plist]).checked()
            }
        }
    }

    struct CommandResult {
        let name: String
        let status: Int32
        let output: String

        func checked() throws -> String {
            guard status == 0 else { throw LiveFailure.processFailed(name, status) }
            return output
        }
    }

    // killall exits 1 for no match and for a refused signal alike; only no match leaves nothing to restart.
    static func checkedRestart(_ result: CommandResult) throws {
        if result.status == 1, result.output.contains("No matching processes") { return }
        _ = try result.checked()
    }

    // Peel's Subprocess limits; this thread alone signals and reaps, so a signal never meets a reused PID.
    static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 10,
        grace: TimeInterval = 2,
        drain: TimeInterval = 0.5
    ) throws -> CommandResult {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { throw LiveFailure.couldNotStart(path) }
        let (reader, writer) = (ends[0], ends[1])
        defer { close(reader) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writer, 1)
        posix_spawn_file_actions_adddup2(&actions, writer, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { (argv + environment).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, path, &actions, &attributes, argv, environment)
        close(writer)
        guard spawned == 0 else { throw LiveFailure.couldNotStart(path) }
        let child = pid

        let clock = ContinuousClock()
        let stopAt = clock.now + .seconds(timeout)
        let killAt = stopAt + .seconds(grace)
        let abandonAt = killAt + .seconds(grace)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var status: Int32 = 0
        var exitedAt: ContinuousClock.Instant?
        var isOpen = true
        var timedOut = false
        var killed = false
        while true {
            let now = clock.now
            if exitedAt == nil {
                let reaped = waitpid(child, &status, WNOHANG)
                if reaped == child { exitedAt = now }
                if reaped < 0, errno != EINTR { (status, exitedAt) = (-1, now) }
            }
            if let exitedAt {
                if !isOpen || now >= exitedAt + .seconds(drain) { break }
            } else if now >= abandonAt {
                // A child stuck in the kernel survives SIGKILL; reap it later and signal it never again.
                DispatchQueue.global(qos: .utility).async { while waitpid(child, nil, 0) < 0, errno == EINTR {} }
                break
            } else if now >= killAt, !killed {
                kill(child, SIGKILL)
                killed = true
            } else if now >= stopAt, !timedOut {
                kill(child, SIGTERM)
                timedOut = true
            }
            guard isOpen else {
                _ = poll(nil, 0, 20)
                continue
            }
            var waiting = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, 20) > 0 else { continue }
            let count = Darwin.read(reader, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer[0..<count])
            } else if count == 0 || errno != EINTR {
                isOpen = false
            }
        }
        guard !timedOut, exitedAt != nil, status & 0x7f == 0 else { throw LiveFailure.stopped(path) }
        guard let text = String(data: output, encoding: .utf8) else { throw LiveFailure.invalidProcessOutput }
        return CommandResult(name: path, status: (status >> 8) & 0xff, output: text)
    }
}
