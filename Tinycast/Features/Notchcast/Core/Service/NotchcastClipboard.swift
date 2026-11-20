/// Clipboard history's pair around a pasteboard write Notchcast makes itself.
struct NotchcastClipboardMutation {
    /// Records a copy the history poller has not read yet, before the write replaces it.
    let prepare: @MainActor () -> Void
    /// Baselines the poller on the write's change count, so it never records the write as a copy.
    let synchronize: @MainActor (_ changeCount: Int) -> Void

    static let none = NotchcastClipboardMutation(prepare: {}, synchronize: { _ in })
}

extension NotchcastContext {
    /// Call before writing the general pasteboard, so the user's last copy reaches history first.
    func prepareClipboardMutation() { services.clipboard.prepare() }

    /// Call with the change count of each own write; a foreign write since then is still recorded.
    func synchronizeClipboard(changeCount: Int) { services.clipboard.synchronize(changeCount) }
}
