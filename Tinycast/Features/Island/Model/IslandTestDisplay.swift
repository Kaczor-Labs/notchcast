/// Verify runs never take a real Mac's own screen; a VM guest has only its main display to give.
enum IslandTestDisplay {
    static func accepts(isMain: Bool, isBuiltin: Bool, inGuest: Bool) -> Bool {
        !isBuiltin && (!isMain || inGuest)
    }
}
