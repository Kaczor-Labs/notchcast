// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift @ 20230794 (GPL-3.0).
// Application groups draw on Peel's AppInspector.swift @ 20230794 (GPL-3.0).
import AppKit
import Security

struct CleanerRunningApps: Sendable {
    var running: Set<String> = []
    var own: Set<String> = []
    var runningBundles: Set<URL> = []
    var ownBundle: URL?
    private(set) var groupMembershipUnknown = false

    func holds(_ owner: String) -> Bool {
        running.contains(CleanerPolicy.appKey(owner)) || running.contains(CleanerPolicy.appKey(
            CleanerPolicy.groupOwner(owner)))
    }

    func includingGroups(read: (URL) -> [String]?) -> Self {
        var names = self
        for bundle in runningBundles {
            guard let groups = read(bundle) else {
                names.groupMembershipUnknown = true
                continue
            }
            names.running.formUnion(groups.map { CleanerPolicy.appKey(CleanerPolicy.groupOwner($0)) })
        }
        if let ownBundle, let groups = read(ownBundle) {
            names.own.formUnion(groups.map { CleanerPolicy.appKey(CleanerPolicy.groupOwner($0)) })
        } else if ownBundle != nil {
            names.groupMembershipUnknown = true
        }
        return names
    }

    static func applicationGroups(at url: URL) -> [String]? {
        var code: SecStaticCode?
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
            let signingInfo = information as? [String: Any]
        else { return nil }
        guard let value = signingInfo[kSecCodeInfoEntitlementsDict as String] else { return [] }
        guard let entitlements = value as? [String: Any] else { return nil }
        guard let groups = entitlements["com.apple.security.application-groups"] else { return [] }
        return groups as? [String]
    }

    @MainActor
    static func live() -> Self {
        var names = Self()
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            let keys = [
                app.bundleIdentifier,
                app.bundleIdentifier.map { $0 + ".ShipIt" },
                app.bundleIdentifier?.split(separator: ".").last.map(String.init),
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.bundleURL?.pathComponents.first { $0.hasSuffix(".app") }.map {
                    String($0.dropLast(".app".count))
                },
                app.localizedName
            ].compactMap { $0 }.map(CleanerPolicy.appKey).filter { !$0.isEmpty }
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                names.own.formUnion(keys)
                names.ownBundle = app.bundleURL
            } else {
                names.running.formUnion(keys)
                if let bundle = app.bundleURL { names.runningBundles.insert(bundle) }
            }
        }
        return names
    }
}
