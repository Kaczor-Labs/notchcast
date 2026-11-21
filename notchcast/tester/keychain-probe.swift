import Foundation

// Drives the app's own KeychainSecretStore; keychain.sh compiles it with that file into a job-local keychain.
@main
struct KeychainProbe {
    static func main() throws {
        let store = KeychainSecretStore(scope: "tester", bundleIdentifier: "app.notchcast.dev")
        let account = UUID()
        try store.setSecret("tester-value-1", for: account)
        guard try store.hasSecret(for: account), try store.secret(for: account) == "tester-value-1" else { exit(1) }
        try store.setSecret("tester-value-2", for: account)
        guard try store.secret(for: account) == "tester-value-2" else { exit(1) }
        print("account: \(account.uuidString)")
        print("set, has, read, update: ok")
    }
}
