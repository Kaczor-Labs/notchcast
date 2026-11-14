import AppKit
import SwiftUI

struct ViewportPlacement: ViewModifier {
    @State private var bounds = CGRect.zero

    func body(content: Content) -> some View {
        Color.clear.frame(height: 0)
            .background(WindowBounds(bounds: $bounds))
            .overlay(alignment: .topLeading) {
                content.frame(width: bounds.width > 0 ? bounds.width : nil)
                    .offset(x: bounds.minX, y: bounds.minY)
            }
    }
}

private struct WindowBounds: NSViewRepresentable {
    @Binding var bounds: CGRect

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.report = { if bounds != $0 { bounds = $0 } }
        view.scheduleReport()
    }

    final class Probe: NSView {
        override var isFlipped: Bool { true }
        var report: ((CGRect) -> Void)?
        private var resizeObserver: NotificationCenter.ObservationToken?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            resizeObserver = nil
            if let window {
                resizeObserver = NotificationCenter.default.addObserver(of: window, for: WindowDidResize.self) { [weak self] _ in
                    self?.scheduleReport()
                }
            }
            scheduleReport()
        }

        isolated deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }

        override func layout() {
            super.layout()
            scheduleReport()
        }

        func scheduleReport() {
            RunLoop.main.perform(#selector(reportBounds), target: self, argument: nil, order: 0, modes: [.common])
        }

        @objc private func reportBounds() {
            guard let root = window?.contentView else { return }
            let rect = convert(root.bounds, from: root)
            report?(rect)
        }
    }
}
