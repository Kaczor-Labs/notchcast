import CoreGraphics
import Observation

/// The open editor's state: the untouched capture and the document drawn over it.
@MainActor
@Observable
final class CaptureEditorSession {
    let image: CGImage
    var document: AnnotationDocument
    private let finish: @MainActor (CaptureEditorOutcome) -> Void

    init(image: CGImage, scale: CGFloat, finish: @escaping @MainActor (CaptureEditorOutcome) -> Void) {
        self.image = image
        document = AnnotationDocument(size: CGSize(width: image.width, height: image.height), scale: scale)
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
