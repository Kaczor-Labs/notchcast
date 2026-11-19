import Foundation

/// What Notchcast trusts from Soloist's data folder before it hands over the key or opens the socket.
enum SoloistLaunchRules {
    /// Soloist binds where `--ws 127.0.0.1:0` says; the socket has no authentication.
    static let loopback = "127.0.0.1"

    static func pid(_ text: String?) -> Int32? {
        guard let text, let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else {
            return nil
        }
        return pid
    }

    /// Both files are required: a missing `ws.addr` means a socket we cannot place on loopback.
    static func socketURL(port: String?, address: String?) -> URL? {
        guard let port, let number = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(number),
              address?.trimmingCharacters(in: .whitespacesAndNewlines) == loopback
        else { return nil }
        return URL(string: "ws://\(loopback):\(number)")
    }

    /// A running Soloist is ours only if it is the installed file, signed by Spotify, and not being stopped.
    static func adoptable(runningPath: String?, installedPath: String, signed: Bool, stopping: Bool) -> Bool {
        guard let runningPath, !stopping, signed else { return false }
        return URL(filePath: runningPath).standardizedFileURL.path == URL(filePath: installedPath).standardizedFileURL.path
    }
}
