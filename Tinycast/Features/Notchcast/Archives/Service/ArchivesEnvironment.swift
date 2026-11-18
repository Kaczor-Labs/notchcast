import Foundation

/// Everything the module needs from the Mac; the harness passes fakes for each.
@MainActor
struct ArchivesEnvironment {
    /// The queue as last saved, so a relaunch resumes it.
    var journal: URL
    var extractor: ArchiveExtractor
    /// Hands every file the system asks Notchcast to open to the closure; `nil` stops.
    var routeOpens: (((@MainActor ([URL]) -> Void))?) -> Void
    /// True makes Notchcast the default app for archives; false hands back what it still holds.
    var setDefaultApp: (Bool) -> Void
    var reveal: (URL) -> Void
    var pickArchives: () -> [URL]
}
