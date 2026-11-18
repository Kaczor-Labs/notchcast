import AppKit

extension AgentsSystem {
    @MainActor static var live: AgentsSystem {
        let folder = AppPaths.applicationSupport().appending(path: "Feeds", directoryHint: .isDirectory)
        return AgentsSystem(
            folder: folder,
            prepare: { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) },
            read: { AgentsFeedReader.file(at: folder.appending(path: $0, directoryHint: .notDirectory)) },
            watch: { onChange in
                let watcher = AgentsFolderWatcher(folder: folder, onChange: onChange)
                watcher.start()
                return { watcher.stop() }
            },
            wake: { seconds, action in
                let task = Task {
                    guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
                    action()
                }
                return { task.cancel() }
            },
            open: { NSWorkspace.shared.open($0) },
            region: { AgentsRegion(locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent) })
    }
}
