import Foundation

/// Reads t3chad's waits file on launch and on every change, announces each new wait once, lists them all (#1462).
@MainActor
final class ThreadsModule: NotchcastModule {
    let context: NotchcastContext
    private let openURL: @MainActor (URL) -> Void
    private let sleep: @MainActor (Duration) async throws -> Void
    private let home: URL
    private var watcher: ThreadsWatcher?
    private var document: ThreadsDocument?
    private var configured = false
    private var readFailed = false
    private var expiry: Task<Void, Never>?
    private var reading: Task<Void, Never>?
    private var generation = 0
    private var rows: [ThreadsDocument.Wait] = []
    private var commandSlugs: [String] = []

    init(context: NotchcastContext, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         open: @escaping @MainActor (URL) -> Void,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.context = context
        self.home = home
        openURL = open
        self.sleep = sleep
    }

    private var preferences: ThreadsPreferences { ThreadsPreferences(defaults: context.defaults, home: home) }

    func start() {
        context.presenter.watchPages(id: ThreadsPage.id) { [weak self] visible in
            guard visible, let self else { return }
            if watcher?.isWatching == false { reload() } else { post() }
        }
        reload()
    }

    func stop() {
        reading?.cancel()
        reading = nil
        expiry?.cancel()
        expiry = nil
        watcher?.cancel()
        watcher = nil
        context.presenter.watchPages(id: ThreadsPage.id, onChange: nil)
        context.presenter.setPage(nil, id: ThreadsPage.id, onAction: nil)
        context.presenter.setStatus(nil, for: ThreadsPage.id, onTap: nil)
    }

    /// The launcher command and its hotkey.
    func showPage() { context.presenter.showPage(id: ThreadsPage.id) }

    /// Settings named another file: forget the old one's list and read the new one.
    func settingsChanged() {
        watcher?.cancel()
        watcher = nil
        document = nil
        reload()
    }

    /// Arms the watcher if it is down and reads the file; the task lets a harness await the read.
    @discardableResult
    func reload() -> Task<Void, Never> {
        let url = preferences.waitsURL
        if watcher?.isWatching != true {
            watcher?.cancel()
            let watcher = ThreadsWatcher(fileURL: url) { [weak self] in self?.reload() }
            watcher.arm()
            self.watcher = watcher
        }
        generation += 1
        let current = generation
        reading?.cancel()
        let task = Task { [weak self] in
            let read = await ThreadsFile.read(url)
            guard let self else { return }
            guard !Task.isCancelled, current == generation else {
                await reading?.value
                return
            }
            apply(read)
        }
        reading = task
        return task
    }

    /// Only a T3 link leaves the add-on, whatever the file says.
    func open(_ url: URL) {
        guard ThreadsLink.isOpenable(url) else { return }
        openURL(url)
    }

    /// A missing or broken read keeps the last good list, shown at once as "not reporting".
    private func apply(_ read: ThreadsRead) {
        configured = true
        switch read {
        case .missing, .unreadable:
            readFailed = true
        case .loaded(let loaded):
            readFailed = false
            document = loaded
        }
        announce()
        post()
    }

    private var board: ThreadsBoard {
        ThreadsBoard(configured: configured, document: document, now: context.now(), readFailed: readFailed)
    }

    private func announce() {
        let board = board
        guard let document = board.document, !board.readFailed else { return }
        let before = preferences.shown
        var shown = before
        let fresh = shown.take(board.announceable, present: document.waits)
        if shown != before { preferences.shown = shown }
        guard !fresh.isEmpty else { return }
        for (notice, wait) in ThreadsPage.notices(fresh) {
            let link = wait.flatMap(ThreadsLink.url)
            context.presenter.post(notice) { [weak self] in
                if let link { self?.open(link) } else { self?.showPage() }
            }
        }
    }

    func post() {
        let board = board
        rows = ThreadsPage.rows(board)
        context.presenter.setPage(ThreadsPage.page(board), id: ThreadsPage.id) { [weak self] action in
            self?.act(action)
        }
        context.presenter.setStatus(ThreadsPage.status(board), for: ThreadsPage.id) { [weak self] in
            self?.showPage()
        }
        publishCommands(board)
        expire(board)
    }

    /// A writer that stops quietly turns the list silent on time; this only republishes, never reads.
    private func expire(_ board: ThreadsBoard) {
        expiry?.cancel()
        expiry = nil
        guard let deadline = board.freshUntil else { return }
        let wait = deadline.timeIntervalSince(board.now) + 1
        expiry = Task { [weak self, sleep] in
            do { try await sleep(.seconds(wait)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.post()
        }
    }

    private func act(_ action: String) {
        if action == IslandPage.refreshAction {
            reload()
        } else if action.hasPrefix(ThreadsPage.rowPrefix), let index = Int(action.dropFirst(ThreadsPage.rowPrefix.count)),
                  rows.indices.contains(index), let link = ThreadsLink.url(rows[index]) {
            open(link)
        }
    }

    /// One command per waiting thread; only a change, target included, reaches the launcher.
    private func publishCommands(_ board: ThreadsBoard) {
        let commands = ThreadsCommands.commands(board.waiting, switchID: ThreadsPreferences.switchID)
        let slugs = commands.map { "\($0.command.slug)\u{1F}\($0.command.name)\u{1F}\($0.command.symbol)\u{1F}\($0.link)" }
        guard slugs != commandSlugs else { return }
        commandSlugs = slugs
        context.setCommands(commands.map(\.command))
    }
}

/// Launcher commands for waiting threads; a slug comes from the wait's stable id, never a counter.
enum ThreadsCommands {
    static let slugPrefix = "thread-"

    /// The newest wait per thread wins, so asks that share a thread share one command.
    static func commands(_ waits: [ThreadsDocument.Wait], switchID: String) -> [(command: NotchcastCommand, link: URL)] {
        var seen: Set<String> = []
        return waits.compactMap { wait in
            guard let id = wait.id, let link = ThreadsLink.url(wait), seen.insert(link.absoluteString).inserted else {
                return nil
            }
            let slug = slugPrefix + String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
            guard seen.insert(slug).inserted else { return nil }
            return (NotchcastCommand(
                slug: slug, name: ThreadsBoard.title(wait), symbol: ThreadsPage.symbol(wait), switchID: switchID,
                keywords: [wait.machine] + (ThreadsPage.detail(wait).map { [$0] } ?? []),
                run: { $0.module(ThreadsModule.self)?.open(link) }), link)
        }
    }
}
