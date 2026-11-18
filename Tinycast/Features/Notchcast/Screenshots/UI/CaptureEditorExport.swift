import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The annotated result as a PNG file, rendered only when a drag out of the editor drops.
enum CaptureEditorExport {
    static func provider(image: CGImage, document: AnnotationDocument) -> NSItemProvider {
        let name = ScreenshotFileName.name(date: Date(), timeZone: .current)
        let provider = NSItemProvider()
        provider.suggestedName = (name as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all
        ) { completion in
            do {
                let folder = FileManager.default.temporaryDirectory.appending(path: "Capture Editor \(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: name)
                try AnnotationRenderer.png(document.finished(), over: image).write(to: url)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }
}
