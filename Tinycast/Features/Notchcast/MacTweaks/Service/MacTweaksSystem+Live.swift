// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

extension MacTweaksSystem {
    private enum LiveFailure: Error {
        case unsupportedPreference
        case invalidTarget
        case invalidValue
        case invalidProcessOutput
        case refused
        case processFailed(String, Int32)
        case stopped(String)
    }

    // killall exits 1 when no process matched, so there is nothing to restart.
    static let killallDone: Set<Int32> = [0, 1]

    static func live() -> Self {
        let session = "gui/\(getuid())"
        return Self(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            journalFolder: AppPaths.applicationSupport().appending(path: "Notchcast/MacTweaks", directoryHint: .isDirectory),
            read: { target in
                try read(target, synchronize: true) { try disabledServices(session: session) }
            },
            readAll: { targets in
                var synchronized: Set<String> = []
                var services: Result<Set<String>, any Error>?
                func disabled() throws -> Set<String> {
                    let result = services ?? Result { try disabledServices(session: session) }
                    services = result
                    return try result.get()
                }
                return Dictionary(targets.map { target in
                    var synchronize = true
                    if case .preference(let domain, _, _) = target.canonical {
                        synchronize = synchronized.insert(domain).inserted
                    }
                    return (target, Result { try read(target, synchronize: synchronize, disabled: disabled) })
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
                _ = try run("/usr/bin/killall", [process.rawValue]).checked(accepting: killallDone)
            },
            now: { Date() }
        )
    }

    private static func read(
        _ target: MacTweakTarget, synchronize: Bool, disabled: () throws -> Set<String>
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
        _ domain: String, key: String, appOnly: Bool, synchronize: Bool = true
    ) throws -> Reading {
        let global = domain == "NSGlobalDomain" || domain == ".GlobalPreferences"
        let application = global ? kCFPreferencesAnyApplication : domain as CFString
        let name = key as CFString
        if synchronize, !(global
            ? CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            : CFPreferencesAppSynchronize(application)) {
            throw LiveFailure.refused
        }
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
        guard try readPreference(domain, key: key, appOnly: appOnly).block == nil else { throw LiveFailure.refused }
        let global = domain == "NSGlobalDomain" || domain == ".GlobalPreferences"
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
            guard let data = FileManager.default.contents(atPath: path),
                  let dictionary = try? PropertyListSerialization.propertyList(
                    from: data, format: nil
                  ) as? [String: Any],
                  let value = dictionary[key] else { continue }
            return value
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

        func checked(accepting success: Set<Int32> = [0]) throws -> String {
            guard success.contains(status) else { throw LiveFailure.processFailed(name, status) }
            return output
        }
    }

    // Peel's limit for launchctl and killall: asked to stop after `timeout`, killed after 2 s more.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> CommandResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        let exit = try process.runObservingExit()
        let stop = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: stop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        stop.cancel()
        guard process.terminationReason == .exit else { throw LiveFailure.stopped(path) }
        guard let text = String(data: data, encoding: .utf8) else { throw LiveFailure.invalidProcessOutput }
        return CommandResult(name: path, status: process.terminationStatus, output: text)
    }
}
