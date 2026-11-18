import AppKit

/// Takes the open-documents event while Archives runs; stock Tinycast opens no files, so nothing is lost.
@MainActor
final class ArchiveOpenHandler: NSObject {
    private var onOpen: (@MainActor ([URL]) -> Void)?

    func route(_ handler: (@MainActor ([URL]) -> Void)?) {
        let events = NSAppleEventManager.shared()
        let eventClass = AEEventClass(kCoreEventClass)
        let eventID = AEEventID(kAEOpenDocuments)
        onOpen = handler
        if handler == nil {
            events.removeEventHandler(forEventClass: eventClass, andEventID: eventID)
        } else {
            events.setEventHandler(
                self, andSelector: #selector(open(_:reply:)), forEventClass: eventClass, andEventID: eventID)
        }
    }

    @objc private func open(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let files = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = files.numberOfItems == 0
            ? [files.fileURLValue].compactMap { $0 }
            : (1...files.numberOfItems).compactMap { files.atIndex($0)?.fileURLValue }
        onOpen?(urls)
    }
}
