// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift @ 20230794 (GPL-3.0).
import AppKit

struct CleanerRunningApps: Sendable {
    var running: Set<String> = []
    var own: Set<String> = []

    func holds(_ item: URL) -> Bool {
        running.contains(CleanerPolicy.appKey(item.lastPathComponent))
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
                app.localizedName
            ].compactMap { $0 }.map(CleanerPolicy.appKey).filter { !$0.isEmpty }
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                names.own.formUnion(keys)
            } else {
                names.running.formUnion(keys)
            }
        }
        return names
    }
}
