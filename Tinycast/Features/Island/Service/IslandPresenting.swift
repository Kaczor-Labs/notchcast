import Foundation

/// The one way code outside `Features/Island/` puts anything on the island.
@MainActor
protocol IslandPresenting: AnyObject {
    /// The one level call for every source, named by `level.source`; nothing is volume-specific.
    func showLevel(_ level: IslandLevel)
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?)
    func end(notice id: String)
    func setStatus(_ status: IslandStatus?, for id: String)
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void)
}

/// Accepts every call and shows nothing yet; rendering arrives with the live states.
@MainActor
final class IslandPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
