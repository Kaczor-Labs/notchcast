// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's drag-out: the result as a dated file in its own temporary folder.

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The annotated result as a PNG file, rendered only when a drag out of the editor drops.
enum CaptureEditorExport {
    static func provider(_ document: AnnotationDocument) -> NSItemProvider {
        let name = ScreenshotFileName.name(date: Date(), timeZone: .current)
        let provider = NSItemProvider()
        provider.suggestedName = (name as NSString).deletingPathExtension
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all
        ) { completion in
            do {
                // Its own folder, so two drags in one second never replace each other's file.
                let folder = FileManager.default.temporaryDirectory.appending(path: "Capture Editor \(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: name)
                try AnnotationRenderer.png(document.finished()).write(to: url)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }
}
