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
    /// The running sensitive-text search, if any.
    private(set) var search: Task<Void, Never>?
    private let finish: @MainActor (CaptureEditorOutcome) -> Void
    private let find: @MainActor (CGImage) async -> [CGRect]

    init(
        image: CGImage, scale: CGFloat, find: @escaping @MainActor (CGImage) async -> [CGRect],
        finish: @escaping @MainActor (CaptureEditorOutcome) -> Void
    ) {
        document = AnnotationDocument(image: image, scale: scale, seed: .random(in: .min ... .max))
        self.find = find
        self.finish = finish
    }

    /// One search at a time; its result is dropped when the image changed meanwhile, by a crop or an undo.
    func coverSensitiveText() {
        guard search == nil else { return }
        let image = document.image
        search = Task {
            let covers = await find(image)
            guard !Task.isCancelled else { return }
            search = nil
            if document.image === image { document.cover(covers) }
        }
    }

    /// The editor is closing: a running search is cancelled and its result never lands.
    func end() {
        search?.cancel()
        search = nil
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
