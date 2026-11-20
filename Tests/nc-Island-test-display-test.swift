// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandTestDisplay.swift

@main
struct IslandTestDisplayTest {
    static func main() {
        precondition(IslandTestDisplay.accepts(isMain: false, isBuiltin: false, inGuest: false))
        precondition(!IslandTestDisplay.accepts(isMain: true, isBuiltin: false, inGuest: false))
        precondition(!IslandTestDisplay.accepts(isMain: true, isBuiltin: true, inGuest: false))
        precondition(!IslandTestDisplay.accepts(isMain: false, isBuiltin: true, inGuest: false))
        precondition(IslandTestDisplay.accepts(isMain: true, isBuiltin: false, inGuest: true))
        precondition(IslandTestDisplay.accepts(isMain: false, isBuiltin: false, inGuest: true))
        precondition(!IslandTestDisplay.accepts(isMain: true, isBuiltin: true, inGuest: true))
        print("PASS IslandTestDisplay main display only in a guest, built-in never")
    }
}
