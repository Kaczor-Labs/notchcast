// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/ColorPickerAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Service/ColorPickerSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Service/ColorPickerModule.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum ColorPickerCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(ColorPickerAddon.self) }
}

// The shipped `live` system and settings UI are left out: these stand in so the descriptor compiles.
struct ColorPickerSettingsView: View {
    init(defaults: UserDefaults, copy: @escaping @MainActor (ColorValue) -> Void) {}
    var body: some View { EmptyView() }
}
extension ColorPickerSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
