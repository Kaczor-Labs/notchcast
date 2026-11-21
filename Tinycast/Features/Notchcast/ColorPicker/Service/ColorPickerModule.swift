import Foundation

/// One sampler at a time; a pick answered after switch-off or a newer pick is dropped.
@MainActor
final class ColorPickerModule: NotchcastModule {
    static let switchID = ColorPickerAddon.switches[0].id
    static let symbol = "eyedropper"
    static let noticeID = "colorPicker.copied"

    private let context: NotchcastContext
    private let system: ColorPickerSystem
    private var running = false
    private var operation: UUID?

    init(context: NotchcastContext, system: ColorPickerSystem) {
        self.context = context
        self.system = system
    }

    func start() { running = true }

    func stop() {
        running = false
        operation = nil
        context.presenter.end(notice: Self.noticeID)
    }

    func pick() {
        guard running, operation == nil else { return }
        let id = UUID()
        operation = id
        system.sample { [weak self] color in
            guard let self, operation == id else { return }
            operation = nil
            guard let color else { return }
            if copy(color) { remember(color) }
        }
    }

    /// Copies in the chosen format and reports it; true when the clipboard took it.
    @discardableResult
    func copy(_ color: ColorValue) -> Bool {
        let value = ColorPickerFormat(stored: context.defaults.string(forKey: ColorPickerFormat.defaultsKey))
            .string(for: color)
        let copied = system.copy(value)
        context.presenter.post(IslandNotice(
            id: Self.noticeID, symbol: Self.symbol,
            text: copied ? value : String(localized: "Could not copy to clipboard.", table: "NotchcastColorPicker"),
            isFailure: !copied,
            swatch: copied ? IslandSwatch(red: color.red, green: color.green, blue: color.blue) : nil), onTap: nil)
        return copied
    }

    private func remember(_ color: ColorValue) {
        let key = ColorPickerHistory.defaultsKey
        context.defaults.set(ColorPickerHistory.adding(color, to: context.defaults.string(forKey: key) ?? ""), forKey: key)
    }
}
