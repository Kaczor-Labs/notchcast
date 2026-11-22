// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastCodeCheck.swift
import Darwin
import Foundation

@main
struct NotchcastCodeCheckTest {
    static let apple = "anchor apple"
    static let invalid = "anchor apple and"
    static let tailscale = """
        anchor apple generic and (identifier "io.tailscale.ipn.macsys" or identifier "io.tailscale.ipn.macos") \
        and (certificate leaf[field.1.2.840.113635.100.6.1.9] \
        or certificate 1[field.1.2.840.113635.100.6.2.6] \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "W5364U7YZB")
        """

    static func main() throws {
        let echo = URL(filePath: "/bin/echo")
        precondition(NotchcastCodeCheck.file(echo, satisfies: apple), "Apple-signed file must pass")
        precondition(!NotchcastCodeCheck.file(echo, satisfies: tailscale), "Wrong publisher requirement must fail")
        precondition(!NotchcastCodeCheck.file(echo, satisfies: invalid), "Malformed file requirement must fail")

        let files = FileManager.default
        let directory = files.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }

        let script = directory.appending(path: "unsigned")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        precondition(!NotchcastCodeCheck.file(script, satisfies: apple), "Unsigned executable must fail")
        let missing = directory.appending(path: "missing")
        precondition(!NotchcastCodeCheck.file(missing, satisfies: apple), "Missing file must fail")

        let results = checkSuspendedEcho()
        precondition(results.apple, "Apple-signed process must pass")
        precondition(!results.tailscale, "Wrong process publisher requirement must fail")
        precondition(!results.invalid, "Malformed process requirement must fail")
        print("Notchcast code signature checks passed")
    }

    private static func checkSuspendedEcho() -> (apple: Bool, tailscale: Bool, invalid: Bool) {
        var attributes: posix_spawnattr_t?
        let initialized = posix_spawnattr_init(&attributes)
        precondition(initialized == 0, "Could not initialize spawn attributes")
        defer { posix_spawnattr_destroy(&attributes) }
        let configured = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_START_SUSPENDED))
        precondition(configured == 0, "Could not set suspended spawn flag")

        var pid: pid_t = 0
        let status = "/bin/echo".withCString { path in
            var arguments = [UnsafeMutablePointer(mutating: path), nil]
            var environment: [UnsafeMutablePointer<CChar>?] = [nil]
            return posix_spawn(&pid, path, nil, &attributes, &arguments, &environment)
        }
        precondition(status == 0 && pid > 0, "Could not spawn suspended echo: \(status)")
        defer {
            let killed = kill(pid, SIGKILL)
            precondition(killed == 0 || errno == ESRCH, "Could not kill suspended echo")
            var reaped: pid_t
            repeat { reaped = waitpid(pid, nil, 0) } while reaped == -1 && errno == EINTR
            precondition(reaped == pid, "Could not reap echo")
        }

        return (
            NotchcastCodeCheck.process(pid, satisfies: apple),
            NotchcastCodeCheck.process(pid, satisfies: tailscale),
            NotchcastCodeCheck.process(pid, satisfies: invalid)
        )
    }
}
