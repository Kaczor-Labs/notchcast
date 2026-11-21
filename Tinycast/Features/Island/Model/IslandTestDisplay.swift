/// Verify runs only inside a VM guest, so never on a real Mac's screen; a built-in display never.
enum IslandTestDisplay {
    static func accepts(isBuiltin: Bool, inGuest: Bool) -> Bool {
        inGuest && !isBuiltin
    }
}
