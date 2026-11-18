import AppKit

extension URLCleanerSystem {
    static let live = URLCleanerSystem(
        observe: { ClipboardManager.willCapture = $0 },
        itemTypes: { NSPasteboard.general.pasteboardItems?.map { $0.types.map(\.rawValue) } ?? [] },
        text: { NSPasteboard.general.string(forType: .string) },
        replace: { link in
            let board = NSPasteboard.general
            board.clearContents()
            board.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            board.setString(link, forType: .string)
            board.setData(Data(), forType: ClipboardManager.internalType)
        }
    )
}
