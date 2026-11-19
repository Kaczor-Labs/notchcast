import Foundation

/// How the editor ended: its owner writes the result, or drops it on Discard.
enum CaptureEditorOutcome: Sendable {
    case copy(AnnotationDocument)
    case save(AnnotationDocument)
    case discard
}
