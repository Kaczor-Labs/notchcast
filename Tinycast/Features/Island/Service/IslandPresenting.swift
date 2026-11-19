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
    /// An owner's page in the open island, nil once it has no data; `onAction` gets a button or row id.
    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?)
    /// `onChange` hears true while `id`'s page data is on show in the open island, false once it is not.
    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?)
}

extension IslandPresenting {
    /// A presenter with no open island, like a harness's recorder, shows no pages.
    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {}
    func watchPages(id: String, onChange: (@MainActor (_ visible: Bool) -> Void)?) {}
}
