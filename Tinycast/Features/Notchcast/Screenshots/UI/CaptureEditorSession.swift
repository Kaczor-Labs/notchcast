import CoreGraphics
import Observation

/// The open editor's state: the document being annotated and the way out its owner listens on.
@MainActor
@Observable
final class CaptureEditorSession {
    var document: AnnotationDocument
    private let finish: @MainActor (CaptureEditorOutcome) -> Void

    init(image: CGImage, scale: CGFloat, finish: @escaping @MainActor (CaptureEditorOutcome) -> Void) {
        document = AnnotationDocument(image: image, scale: scale, seed: .random(in: .min ... .max))
        self.finish = finish
    }

    func perform(_ action: AnnotationKeyAction) {
        switch action {
        case .copy: finish(.copy(document.finished()))
        case .save: finish(.save(document.finished()))
        case .discard: finish(.discard)
        default: document.apply(action)
        }
    }
}
