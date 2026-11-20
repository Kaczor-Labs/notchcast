// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandTestDisplay.swift

@main
struct IslandTestDisplayTest {
    static func main() {
        precondition(!IslandTestDisplay.accepts(isBuiltin: false, inGuest: false))
        precondition(!IslandTestDisplay.accepts(isBuiltin: true, inGuest: false))
        precondition(IslandTestDisplay.accepts(isBuiltin: false, inGuest: true))
        precondition(!IslandTestDisplay.accepts(isBuiltin: true, inGuest: true))
        print("PASS IslandTestDisplay only in a guest, built-in never")
    }
}
