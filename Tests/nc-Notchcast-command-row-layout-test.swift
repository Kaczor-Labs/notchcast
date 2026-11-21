// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: notchcast/vendor/Obsidian/ObsidianTokens.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastCommandRowLayout.swift
import AppKit
import SwiftUI

/// A command row at the narrowest Settings pane keeps a long name readable instead of squeezing it to
/// nothing beside the alias field, shortcut recorder and checkbox. `NC_AUDIT_RENDERS` keeps the PNGs.
@MainActor
@main
struct CommandRowLayoutTest {
    static let name = "Synchronize project backups to the NAS"
    static var titleWidth: CGFloat = 0
    static var rowWidth: CGFloat = 0
    static var failures = 0

    static func main() {
        precondition(name.count == 38)
        // The Form row's content width at the 420 pt detail minimum, a narrower one, and a roomy one.
        check(width: 360, minimumTitle: 200)
        check(width: 300, minimumTitle: 150)
        check(width: 700, minimumTitle: NotchcastCommandRowLayout<Text, EmptyView, EmptyView>.titleMinimum)
        if failures > 0 { fatalError("\(failures) failure(s)") }
        print("PASS command rows keep a long name readable at every width")
    }

    static func check(width: CGFloat, minimumTitle: CGFloat) {
        titleWidth = 0
        rowWidth = 0
        let row = NotchcastCommandRowLayout {
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
                .background(probe { titleWidth = $0 })
        } trailing: {
            Image(systemName: "trash")
        } controls: { labelsToggle in
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
            Toggle("Show in launcher", isOn: .constant(true))
                .toggleStyle(.checkbox)
                .labelsVisibility(labelsToggle ? .visible : .hidden)
                .fixedSize()
        }
        .background(probe { rowWidth = $0 })
        .frame(width: width)
        .padding(Theme.Spacing.lg)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return fail("width \(width): nothing rendered") }
        if let folder = ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"],
           let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("command-row-\(Int(width)).png"))
        }
        print("width \(width): title \(titleWidth), row \(rowWidth)")
        if titleWidth < minimumTitle { fail("width \(width): title \(titleWidth) < \(minimumTitle)") }
        if rowWidth > width + 0.5 { fail("width \(width): row \(rowWidth) overflows") }
    }

    static func probe(_ record: @escaping @MainActor (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            // ImageRenderer runs no onAppear, so the width is taken as the layout reads it.
            let _ = record(proxy.size.width)
            Color.clear
        }
    }

    static func fail(_ message: String) {
        print("FAIL \(message)")
        failures += 1
    }
}
