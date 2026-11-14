// notchcast-sources: Tinycast/Features/Island/Model/IslandScreenSelection.swift

@main
struct IslandScreenSelectionTest {
    static func main() {
        precondition(IslandScreenSelection.choose(available: [11, 22], preferred: 22, retained: 11) == 22)
        precondition(IslandScreenSelection.choose(available: [11, 22], preferred: 99, retained: 22) == 22)
        precondition(IslandScreenSelection.choose(available: [11, 22], preferred: nil, retained: nil) == 11)
        precondition(IslandScreenSelection.choose(available: [22, 11], preferred: 11, retained: 22) == 11)
        precondition(IslandScreenSelection.choose(available: [], preferred: 11, retained: 22) == nil)
        print("PASS IslandScreenSelection explicit display wins, retained display survives reorder, disconnect falls back")
    }
}
