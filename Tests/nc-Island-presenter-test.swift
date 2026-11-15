// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
import Foundation

@main
struct IslandPresenterTest {
    @MainActor static func main() {
        let island = RecordingIslandPresenter()
        let volume = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.5)
        let sync = IslandNotice(id: "sync", symbol: nil, text: "Syncing", progress: 0.2)
        let timer = IslandStatus(id: "timer", symbol: "timer", text: "4:59", label: "Timer")
        let focus = [IslandMenuRow(id: "25", title: "25 minutes", isChecked: false)]
        let music = [IslandMenuRow(id: "pause", title: "Pause", isChecked: nil)]
        var taps = 0
        var selected: [String] = []

        precondition(volume.range == 0...1 && !sync.isFailure, "Defaults are the standard track and no failure")
        island.showLevel(volume)
        island.post(sync, onTap: { taps += 1 })
        island.setStatus(timer, for: timer.id)
        island.setMenuRows(focus, owner: "focus") { selected.append($0) }
        island.setMenuRows(music, owner: "music") { selected.append($0) }
        precondition(island.calls == [
            .showLevel(volume), .post(sync, tappable: true), .setStatus(timer, id: "timer"),
            .setMenuRows(focus, owner: "focus"), .setMenuRows(music, owner: "music"),
        ], "Every call is recorded in order")

        island.tapNotice()
        precondition(taps == 1, "A notice's tap reaches its caller")
        var synced = sync
        synced.progress = 0.6
        island.post(synced, onTap: nil)
        precondition(island.notice == synced && island.calls.last == .post(synced, tappable: false))

        island.select("25", owner: "focus")
        precondition(selected == ["25"], "Selecting a row reaches its owner")
        let replaced = [IslandMenuRow(id: "50", title: "50 min", isChecked: nil)]
        island.setMenuRows(replaced, owner: "focus") { selected.append("new " + $0) }
        island.select("50", owner: "focus")
        precondition(island.menuOwners == ["focus", "music"] && selected == ["25", "new 50"]
                     && island.calls.last == .setMenuRows(replaced, owner: "focus"),
                     "Same owner replaces its rows and handler in place")
        island.setMenuRows([], owner: "focus") { _ in }
        precondition(island.menuOwners == ["music"], "setMenuRows([]) removes the owner")

        island.setStatus(nil, for: timer.id)
        precondition(island.statuses.isEmpty && island.calls.last == .setStatus(nil, id: "timer"),
                     "setStatus(nil) clears")
        island.end(notice: "other")
        precondition(island.notice == synced, "Ending another id leaves the notice")
        island.end(notice: "sync")
        precondition(island.notice == nil && island.calls.last == .end(notice: "sync"), "end(notice:) removes")
        precondition(island.calls.count == 11)
        print("Island presenter: the fake records calls in order and clears status, menu rows and notices")
    }
}

/// Records every presenter call in order and keeps the state a caller can observe.
@MainActor
final class RecordingIslandPresenter: IslandPresenting {
    enum Call: Equatable {
        case showLevel(IslandLevel)
        case post(IslandNotice, tappable: Bool)
        case end(notice: String)
        case setStatus(IslandStatus?, id: String)
        case setMenuRows([IslandMenuRow], owner: String)
    }

    private(set) var calls: [Call] = []
    private(set) var notice: IslandNotice?
    private(set) var statuses: [String: IslandStatus] = [:]
    private var onTap: (@MainActor () -> Void)?
    private var menus: [(owner: String, onSelect: @MainActor (String) -> Void)] = []
    var menuOwners: [String] { menus.map(\.owner) }

    func showLevel(_ level: IslandLevel) { calls.append(.showLevel(level)) }

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        calls.append(.post(notice, tappable: onTap != nil))
        self.notice = notice
        self.onTap = onTap
    }

    func end(notice id: String) {
        calls.append(.end(notice: id))
        if notice?.id == id { notice = nil; onTap = nil }
    }

    func setStatus(_ status: IslandStatus?, for id: String) {
        calls.append(.setStatus(status, id: id))
        statuses[id] = status
    }

    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        calls.append(.setMenuRows(rows, owner: owner))
        let index = menus.firstIndex { $0.owner == owner }
        if rows.isEmpty {
            if let index { menus.remove(at: index) }
        } else if let index {
            menus[index].onSelect = onSelect
        } else {
            menus.append((owner, onSelect))
        }
    }

    func tapNotice() { onTap?() }
    func select(_ rowID: String, owner: String) { menus.first { $0.owner == owner }?.onSelect(rowID) }
}
