import Foundation

/// Settings' defaults edits round-trip through the main app without losing or echoing a value.
@main
enum SharedStateMirrorTests {
    @MainActor
    static func main() throws {
        var failures = 0
        var checks = 0
        func check(_ name: String, _ passed: Bool) {
            checks += 1
            if !passed {
                failures += 1
                print("FAIL \(name)")
            }
        }

        try checkDefaultsRoundTrip(check)
        try checkLocalKeys(check)

        print("\(checks - failures)/\(checks) shared state checks passed")
        if failures > 0 { exit(1) }
    }

    @MainActor
    private static func checkDefaultsRoundTrip(_ check: (String, Bool) -> Void) throws {
        let mainDomain = "settings-mirror-main-\(UUID())"
        let settingsDomain = "settings-mirror-child-\(UUID())"
        let main = try require(UserDefaults(suiteName: mainDomain))
        let settings = try require(UserDefaults(suiteName: settingsDomain))
        defer {
            main.removePersistentDomain(forName: mainDomain)
            settings.removePersistentDomain(forName: settingsDomain)
        }
        let aliases = "launcherAliases"
        main.set(["existing": "existing", "removed": "old"], forKey: aliases)
        settings.set(["existing": "existing", "removed": "old"], forKey: aliases)

        var states: [SharedDefaultsState] = []
        var edits: [SharedDefaultsEdit] = []
        let owner = SharedDefaultsMirror(role: .main, defaults: main, domainName: mainDomain, reload: {}) {
            if case .defaultsState(let state) = $0 { states.append(state) }
        }
        let peer = SharedDefaultsMirror(
            role: .settings, defaults: settings, domainName: settingsDomain, reload: {}
        ) {
            if case .defaultsEdit(let edit) = $0 { edits.append(edit) }
        }
        owner.start()
        peer.start()

        main.set(["existing": "main edit", "removed": "old"], forKey: aliases)
        owner.flush()
        settings.set(["existing": "existing", "added": "first edit"], forKey: aliases)
        peer.apply(try require(states.first))
        check(
            "an incoming update preserves a pending edit and removal",
            settings.dictionary(forKey: aliases) as? [String: String] == [
                "existing": "main edit", "added": "first edit"
            ])

        owner.apply(try require(edits.first))
        settings.set(["existing": "main edit", "added": "second edit"], forKey: aliases)
        peer.apply(try require(states.last))
        check(
            "an acknowledgement preserves an edit made while the earlier edit was in flight",
            settings.dictionary(forKey: aliases) as? [String: String] == [
                "existing": "main edit", "added": "second edit"
            ])

        owner.apply(try require(edits.last))
        peer.apply(try require(states.last))
        let expected = ["existing": "main edit", "added": "second edit"]
        check(
            "both stores converge after acknowledgement",
            main.dictionary(forKey: aliases) as? [String: String] == expected
                && settings.dictionary(forKey: aliases) as? [String: String] == expected)
        peer.flush()
        owner.flush()
        check("applied states do not echo", edits.count == 2 && states.count == 3)

        main.set(false, forKey: "switch")
        settings.set(true, forKey: "switch")
        owner.flush()
        peer.apply(try require(states.last))
        check("a pending scalar remains visible until acknowledgement", settings.bool(forKey: "switch"))
        owner.apply(try require(edits.last))
        peer.apply(try require(states.last))
        check(
            "a scalar conflict resolves in the main app's edit order",
            main.bool(forKey: "switch") && settings.bool(forKey: "switch"))
    }

    @MainActor
    private static func checkLocalKeys(_ check: (String, Bool) -> Void) throws {
        let domain = "settings-mirror-local-\(UUID())"
        let defaults = try require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var changes: [SharedChange] = []
        let key = "snippetsEnabled"
        let mirror = SharedDefaultsMirror(
            role: .settings, defaults: defaults, domainName: domain, localKeys: [key], reload: {}
        ) { changes.append($0) }
        mirror.start()
        defaults.set(true, forKey: key)
        defaults.set("equation", forKey: "alias")
        mirror.flush()
        let edits = changes.compactMap { change -> SharedDefaultsEdit? in
            if case .defaultsEdit(let edit) = change { return edit }
            return nil
        }
        let edit = try require(edits.first)
        let after = try PropertyListSerialization.propertyList(from: edit.after, format: nil) as? [String: Any]
        check("capability values stay out of the edit payload", after?[key] == nil && after?["alias"] as? String == "equation")
        let signalledLocalChange = changes.contains {
            if case .localDefaultsChanged = $0 { return true }
            return false
        }
        check("the mirror signals the shared local store without a value", signalledLocalChange)

        let incoming = try PropertyListSerialization.data(fromPropertyList: [key: false], format: .binary, options: 0)
        mirror.apply(SharedDefaultsState(acknowledgedEdit: edit.revision, values: incoming, removed: [key]))
        check("peer payloads cannot write or remove a capability", defaults.bool(forKey: key))
    }

    private static func require<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }
}
