import AppKit

extension ColorPickerSystem {
    static let live = ColorPickerSystem(
        sample: { completion in
            NSColorSampler().show { color in
                let value = color.flatMap(screenValue)
                Task { @MainActor in completion(value) }
            }
        },
        copy: { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        }
    )
}
