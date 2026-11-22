// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: notchcast/vendor/Obsidian/ObsidianTokens.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/UI/NotchcastCommandRowLayout.swift
import AppKit
import SwiftUI

@MainActor
@main
struct CommandRowLayoutTest {
    static let name = "Synchronize project backups to the network storage and verify the copied files"
    static var titleBounds = CGRect.zero
    static var controlsBounds = CGRect.zero
    static var checkboxBounds = CGRect.zero
    static var rowBounds = CGRect.zero
    static var aliasBounds = CGRect.zero
    static var trailingBounds = CGRect.zero

    static func main() {
        let wide = check(windowWidth: 1300, stacked: false)
        let singleLineHeight = titleBounds.height
        let middle = check(windowWidth: 820, stacked: true)
        let narrow = check(windowWidth: 652, stacked: true)
        precondition(titleBounds.height > singleLineHeight, "the narrow title wraps onto another line")
        precondition(wide.width > 60, "the wide checkbox draws more than its checkmark")
        precondition(abs(wide.width - middle.width) < 0.5 && abs(wide.width - narrow.width) < 0.5,
                     "the checkbox keeps its full label at every window width")
        checkIdentity()
        print("PASS command rows keep their names and checkbox labels visible at 652, 820 and 1300 pt")
    }

    static func check(windowWidth: CGFloat, stacked: Bool) -> CGRect {
        let formInsets: CGFloat = 60
        let width = windowWidth - Theme.Size.settingsSidebar - formInsets
        titleBounds = .zero
        controlsBounds = .zero
        checkboxBounds = .zero
        rowBounds = .zero
        aliasBounds = .zero
        trailingBounds = .zero
        let row = NotchcastCommandRow {
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
                .background(probe { titleBounds = $0 })
        } trailing: {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "pencil")
                Image(systemName: "trash")
            }
            .background(probe { trailingBounds = $0 })
        } fields: {
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
                .background(probe { aliasBounds = $0 })
            Color.gray.frame(width: Theme.Size.shortcutRecorder, height: 24)
                .background(probe { controlsBounds = $0 })
        } checkbox: {
            Toggle("Show in launcher", isOn: .constant(true))
                .toggleStyle(.checkbox)
                .background(probe { checkboxBounds = $0 })
        }
        .background(probe { rowBounds = $0 })
        .coordinateSpace(name: "row")
        .frame(width: width)
        .padding(Theme.Spacing.lg)
        .background(Color.black)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        guard let image = renderer.nsImage else { preconditionFailure("width \(width): nothing rendered") }
        if let folder = ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"],
           let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("command-row-\(Int(windowWidth)).png"))
        }
        print("window \(windowWidth), row \(rowBounds): title \(titleBounds), "
              + "fields \(controlsBounds), checkbox \(checkboxBounds)")
        precondition(titleBounds.width >= NotchcastCommandRowLayout.titleMinimum, "title collapsed")
        precondition(rowBounds.width <= width + 0.5, "row exceeds its pane")
        let rowWithTolerance = rowBounds.insetBy(dx: -0.5, dy: -0.5)
        for bounds in [titleBounds, aliasBounds, controlsBounds, checkboxBounds, trailingBounds] {
            precondition(!bounds.isEmpty && rowWithTolerance.contains(bounds), "control exceeds its row: \(bounds)")
        }
        precondition(!checkboxBounds.intersects(controlsBounds), "checkbox overlaps the hotkey field")
        if stacked {
            precondition(controlsBounds.minY >= titleBounds.maxY, "fields should move below the title")
        } else {
            precondition(abs(controlsBounds.midY - titleBounds.midY) < 0.5, "fields should stay inline")
        }
        return checkboxBounds
    }

    static func checkIdentity() {
        var mounted: [NSView] = []
        let row = NotchcastCommandRow {
            Text(name).frame(minWidth: NotchcastCommandRowLayout.titleMinimum)
        } trailing: {
            EmptyView()
        } fields: {
            ControlProbe { mounted.append($0) }
                .frame(width: Theme.Size.shortcutRecorder, height: 24)
            ControlProbe { mounted.append($0) }
                .frame(width: Theme.Size.shortcutRecorder, height: 24)
        } checkbox: {
            Toggle("Show in launcher", isOn: .constant(true))
                .toggleStyle(.checkbox)
        }
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: row)
        host.setFrameSize(NSSize(width: 700, height: 120))
        host.layoutSubtreeIfNeeded()
        precondition(mounted.count == 2, "the two controls mount once at the wide width")
        let widePosition = mounted[0].convert(.zero, to: host) as CGPoint

        host.setFrameSize(NSSize(width: 300, height: 120))
        host.layoutSubtreeIfNeeded()
        let narrowPosition = mounted[0].convert(.zero, to: host) as CGPoint
        precondition(widePosition.y != narrowPosition.y, "resizing moves the existing controls")
        precondition(mounted.count == 2 && mounted.allSatisfy { $0.isDescendant(of: host) }, "both controls stay mounted")
        print("PASS both control views survive resize")
    }

    private struct ControlProbe: NSViewRepresentable {
        let mounted: (NSView) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            mounted(view)
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {}
    }

    static func probe(_ record: @escaping @MainActor (CGRect) -> Void) -> some View {
        GeometryReader { proxy in
            record(proxy.frame(in: .named("row")))
            return Color.clear
        }
    }
}
