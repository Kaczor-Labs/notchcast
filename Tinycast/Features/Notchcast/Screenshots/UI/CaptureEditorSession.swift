import CoreGraphics
import Observation

/// The open editor's state: the document, and the mosaic its pixelate marks paint from.
@MainActor
@Observable
final class CaptureEditorSession {
    var document: AnnotationDocument
    private let finish: @MainActor (CaptureEditorOutcome) -> Void
    @ObservationIgnored private var mosaicCache: (image: CGImage, mosaic: CGImage?)?

    init(image: CGImage, scale: CGFloat, finish: @escaping @MainActor (CaptureEditorOutcome) -> Void) {
        document = AnnotationDocument(image: image, scale: scale)
        self.finish = finish
    }

    func perform(_ action: AnnotationKeyAction) {
        if let outcome = document.apply(action) { finish(outcome) }
    }

    /// Made once per image, and only once a pixelate mark needs it; a crop or an undo changes the image.
    func mosaic() -> CGImage? {
        guard document.marks.contains(where: { $0.tool == .pixelate }) else { return nil }
        if let mosaicCache, mosaicCache.image === document.image { return mosaicCache.mosaic }
        var random = SystemRandomNumberGenerator()
        let mosaic = AnnotationRenderer.mosaic(of: document.image, using: &random)
        mosaicCache = (document.image, mosaic)
        return mosaic
    }
}
