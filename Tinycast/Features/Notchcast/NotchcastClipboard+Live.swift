extension NotchcastClipboardMutation {
    /// Clipboard history's own pair, the one `TextInjector` uses.
    @MainActor
    init(core: AppCore) {
        let history = core.clipboardManager
        self.init(
            prepare: { history.prepareForTinycastPasteboardMutation() },
            synchronize: { history.synchronizeAfterTinycastPasteboardMutation(changeCount: $0) })
    }
}
