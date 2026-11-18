// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/ColorPickerAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Service/ColorPickerSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Service/ColorPickerModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

@MainActor var settingsCopy: (@MainActor (ColorValue) -> Void)?

struct ColorPickerSettingsView: View {
    init(defaults: UserDefaults, copy: @escaping @MainActor (ColorValue) -> Void) { settingsCopy = copy }
    var body: some View { EmptyView() }
}

@MainActor
final class Fake {
    var samplers: [@MainActor @Sendable (ColorValue?) -> Void] = []
    var copies: [String] = []
    var copyWorks = true

    /// Answers the open sampler as the user would: a click on a pixel, or Esc for nil.
    func answer(_ color: NSColor?) {
        let sampler = samplers.removeFirst()
        sampler(color.flatMap(ColorPickerSystem.screenValue))
    }
}

@MainActor let fake = Fake()

extension ColorPickerSystem {
    static let live = ColorPickerSystem(
        sample: { fake.samplers.append($0) },
        copy: { text in
            guard fake.copyWorks else { return false }
            fake.copies.append(text)
            return true
        }
    )
}

@MainActor
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

let command = "command:nc-pick-color"

func srgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
}

/// The controller reconciles a switch in a follow-up main-actor task, so this yields until it has.
@MainActor
func settle(_ done: () -> Bool) async {
    for _ in 0..<10_000 where !done() { await Task.yield() }
}

@main
enum ColorPickerModuleTests {
    @MainActor
    static func main() async {
        precondition(ColorPickerAddon.switches.map(\.id) == ["colorPicker"], "v1 switch id")
        precondition(ColorPickerAddon.switches[0].defaultEnabled == false, "off by default, as v1 shipped it")
        precondition(ColorPickerAddon.switches[0].category == .capture, "capture category")
        precondition(ColorPickerAddon.switches[0].requiredGrants.isEmpty, "the system sampler needs no grant")
        precondition(ColorPickerAddon.commands.map(\.id) == [command], "v1 slug keeps its hotkey")
        precondition(ColorPickerAddon.commands[0].name == "Pick Color", "the issue's command name")

        for byte in 0...255 {
            let hex = String(format: "#%02X%02X%02X", byte, 255 - byte, byte / 2)
            let value = ColorPickerSystem.screenValue(srgb(byte, 255 - byte, byte / 2))
            precondition(value.map { ColorPickerFormat.hex.string(for: $0) } == hex, "an sRGB pixel is exact: \(hex)")
        }
        let p3 = ColorPickerSystem.screenValue(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))
        precondition(p3.map { ColorPickerFormat.hex.string(for: $0) } == "#FF0000", "Display P3 red clamps to sRGB red")

        let suite = "nc-ColorPicker-module-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let presenter = RecordingPresenter()
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
            fatalError("Color Picker declares no tap")
        })
        let controller = NotchcastController(
            addons: [ColorPickerAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter)
        controller.start()

        precondition(!controller.run(entryID: command) && fake.samplers.isEmpty, "switch off: no command, no sampler")
        controller.preferences.set("colorPicker", on: true)
        await settle { !controller.enabledCommands.isEmpty }
        precondition(controller.run(entryID: command) && fake.samplers.count == 1, "the command opens the sampler")
        precondition(controller.run(entryID: command) && fake.samplers.count == 1, "a second pick while one is open waits")

        fake.answer(srgb(0x12, 0xAB, 0xEF))
        precondition(fake.copies == ["#12ABEF"], "acceptance 1: a known colour copies its exact hex")
        let notice = presenter.posts.last
        precondition(notice?.text == "#12ABEF" && notice?.symbol == "eyedropper" && notice?.isFailure == false,
                     "the island shows the copied value")
        precondition(defaults.string(forKey: ColorPickerHistory.defaultsKey) == "#12ABEF", "the pick is remembered")

        precondition(controller.run(entryID: command))
        fake.answer(nil)
        precondition(fake.copies.count == 1 && presenter.posts.count == 1, "Esc copies and shows nothing")

        defaults.set("rgb", forKey: ColorPickerFormat.defaultsKey)
        precondition(controller.run(entryID: command))
        fake.answer(srgb(255, 0, 0))
        precondition(fake.copies.last == "rgb(255, 0, 0)", "the chosen format is copied")
        precondition(defaults.string(forKey: ColorPickerHistory.defaultsKey) == "#FF0000 #12ABEF",
                     "history keeps the colour, not the notation")

        fake.copyWorks = false
        precondition(controller.run(entryID: command))
        fake.answer(srgb(0, 0, 255))
        precondition(presenter.posts.last?.text == "Could not copy to clipboard." && presenter.posts.last?.isFailure == true,
                     "a refused clipboard reports")
        precondition(defaults.string(forKey: ColorPickerHistory.defaultsKey) == "#FF0000 #12ABEF",
                     "a pick that never reached the clipboard is not remembered")
        fake.copyWorks = true

        guard let context = controller.context(forSwitch: "colorPicker") else { preconditionFailure("context") }
        _ = ColorPickerAddon.settings[0].view(context)
        defaults.set("hsl", forKey: ColorPickerFormat.defaultsKey)
        settingsCopy?(ColorPickerHistory.colors(defaults.string(forKey: ColorPickerHistory.defaultsKey) ?? "")[1])
        precondition(fake.copies.last == "hsl(198.5deg, 87.4%, 50.4%)", "a recent pick copies again in the chosen format")

        precondition(controller.run(entryID: command))
        let copies = fake.copies.count
        controller.preferences.set("colorPicker", on: false)
        await settle { controller.enabledCommands.isEmpty }
        precondition(presenter.ends.contains("colorPicker.copied"), "switch off ends the notice")
        fake.answer(srgb(1, 2, 3))
        precondition(fake.copies.count == copies, "a pick answered after switch off is dropped")
        precondition(!controller.run(entryID: command), "and the command goes with the switch")

        controller.preferences.set("colorPicker", on: true)
        await settle { !controller.enabledCommands.isEmpty }
        precondition(controller.run(entryID: command) && fake.samplers.count == 1, "a fresh module opens a fresh sampler")
        fake.answer(srgb(0, 0, 0))
        precondition(fake.copies.last == "hsl(0deg, 0%, 0%)", "and copies")
        controller.stop()
        print("nc-ColorPicker-module-test: ok")
    }
}
