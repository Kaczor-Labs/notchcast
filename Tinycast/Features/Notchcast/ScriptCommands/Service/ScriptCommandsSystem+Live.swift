import Darwin
import Foundation

extension ScriptCommandsSystem {
    static let live = ScriptCommandsSystem(
        environment: {
            ScriptInvocation.Environment(
                shell: ProcessInfo.processInfo.environment["SHELL"] ?? accountShell(),
                home: FileManager.default.homeDirectoryForCurrentUser.path,
                isExecutableFile: { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                        && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
                },
                isDirectory: { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                })
        },
        launch: { try ScriptChildProcess(invocation: $0) },
        sleep: { try await Task.sleep(for: $0) },
        makeID: { UUID().uuidString.lowercased() })

    /// The account's login shell, for an app launched without `$SHELL` in its environment.
    private static func accountShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }
}
