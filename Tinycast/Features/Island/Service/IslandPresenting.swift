import Foundation

/// The one way code outside `Features/Island/` puts anything on the island.
@MainActor
protocol IslandPresenting: AnyObject {
    /// The one level call for every source, named by `level.source`; nothing is volume-specific.
    func showLevel(_ level: IslandLevel)
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?)
    func end(notice id: String)
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?)
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void)
}
