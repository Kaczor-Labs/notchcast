import CoreGraphics
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The annotated result as a PNG file, rendered when a drag out of the editor drops.
struct CaptureEditorExport: Transferable {
    let image: CGImage
    let document: AnnotationDocument

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { export in
            let folder = FileManager.default.temporaryDirectory.appending(path: "Capture Editor \(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: ScreenshotFileName.name(date: Date(), timeZone: .current))
            try AnnotationRenderer.png(export.document.finished(), over: export.image).write(to: url)
            return SentTransferredFile(url)
        }
    }
}
