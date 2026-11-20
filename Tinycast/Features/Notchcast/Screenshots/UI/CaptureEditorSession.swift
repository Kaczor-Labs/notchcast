import CoreGraphics
import Foundation
import Observation

/// The open editor's state: the document being annotated and the way out its owner listens on.
@MainActor
@Observable
final class CaptureEditorSession {
    var document: AnnotationDocument
    /// Where drags out of the editor leave their files; the panel removes it on close.
    let dragFolder = FileManager.default.temporaryDirectory.appending(path: "Capture Editor \(UUID().uuidString)")
    private let finish: @MainActor (CaptureEditorOutcome) -> Void

    init(image: CGImage, scale: CGFloat, finish: @escaping @MainActor (CaptureEditorOutcome) -> Void) {
        document = AnnotationDocument(image: image, scale: scale, seed: .random(in: .min ... .max))
        self.finish = finish
    }

    func perform(_ action: AnnotationKeyAction) {
        switch action {
        case .copy: finish(.copy(document.finished()))
        case .save: finish(.save(document.finished()))
        case .saveAs: finish(.saveAs(document.finished()))
        case .close: finish(.close(document.finished()))
        case .discard: finish(.discard)
        case .ignore: break
        default: document.apply(action)
        }
    }
}
