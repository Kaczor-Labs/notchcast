import AppKit

/// The Mac side of Color Picker, injected so a harness fakes it; `.live` is in `+Live`.
struct ColorPickerSystem: Sendable {
    /// Shows the system sampler; answers nil when the user presses Esc.
    let sample: @MainActor @Sendable (@escaping @MainActor @Sendable (ColorValue?) -> Void) -> Void
    let copy: @MainActor @Sendable (String) -> Bool

    /// The sampler answers in the display's space; every format states sRGB, so it converts first.
    nonisolated static func screenValue(_ color: NSColor) -> ColorValue? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return ColorValue(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
