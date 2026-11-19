import SwiftUI

/// An add-on command's one inline field in root search, built as upstream builds a custom command's.
@MainActor
enum NotchcastArgumentAccessory {
    static let field = "argument"

    static func make(
        entry: AppEntry, title: String, vm: PaletteState, metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding, onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory {
        let arguments = [InlineArgument(id: field, title: title, isOptional: true)]
        let key = PaletteState.argumentKey(entry.id, field)
        let text = Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: [field],
            firstIncompleteField: nil,
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: entry.symbolName, tint: entry.settingsOwner?.tint ?? .graphite,
                    value: { _ in text },
                    focused: focus, openOptions: { _ in }, onSubmit: onSubmit
                )
                .id(entry.id))
        )
    }

    static func value(for entryID: String, vm: PaletteState) -> String {
        (vm.commandArguments[PaletteState.argumentKey(entryID, field)] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
