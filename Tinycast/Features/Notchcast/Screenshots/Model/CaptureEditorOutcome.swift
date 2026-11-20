import Foundation

/// How the editor asks to end: its owner writes the result, asks before a close loses work, or drops it.
enum CaptureEditorOutcome: Sendable {
    case copy(AnnotationDocument)
    case save(AnnotationDocument)
    case saveAs(AnnotationDocument)
    case close(AnnotationDocument)
    case discard
}
