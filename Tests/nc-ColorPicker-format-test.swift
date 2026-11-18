// notchcast-sources: Tinycast/Features/Notchcast/ColorPicker/Model/*.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift

import Foundation

@main
enum ColorPickerFormatTests {
    static func main() {
        let teal = ColorValue(red: 0x12 / 255, green: 0xAB / 255, blue: 0xEF / 255)
        precondition(ColorPickerFormat.hex.string(for: teal) == "#12ABEF", "hex is #RRGGBB, upper case")
        precondition(ColorPickerFormat.rgb.string(for: teal) == "rgb(18, 171, 239)", "rgb() states bytes")
        precondition(ColorPickerFormat.hsl.string(for: teal) == "hsl(198.5deg, 87.4%, 50.4%)",
                     "hsl() \(ColorPickerFormat.hsl.string(for: teal))")
        precondition(ColorPickerFormat.swiftUI.string(for: teal) == "Color(red: 0.071, green: 0.671, blue: 0.937)",
                     "SwiftUI Color, sRGB by default")

        let red = ColorValue(red: 1, green: 0, blue: 0)
        precondition(ColorPickerFormat.allCases.map { $0.string(for: red) } == [
            "#FF0000", "rgb(255, 0, 0)", "hsl(0deg, 100%, 50%)", "Color(red: 1.000, green: 0.000, blue: 0.000)",
        ], "pure red in every format")
        let half = ColorValue(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        precondition(ColorPickerFormat.hex.string(for: half) == "#808080", "no format states alpha")

        for byte in 0...255 {
            let value = Double(byte) / 255
            let gray = ColorValue(red: value, green: value, blue: value)
            let fraction = ColorPickerFormat.swiftUI.string(for: gray)
                .split(separator: " ")[1].dropLast()
            precondition(Int((Double(fraction)! * 255).rounded()) == byte, "SwiftUI Color keeps byte \(byte)")
            precondition(ColorPickerFormat.rgb.string(for: gray) == "rgb(\(byte), \(byte), \(byte))", "rgb byte \(byte)")
            precondition(ColorValue.parse(ColorPickerFormat.hsl.string(for: gray))
                .map { ColorPickerFormat.hex.string(for: $0) } == ColorPickerFormat.hex.string(for: gray),
                         "hsl() reads back to the same hex at \(byte)")
        }

        precondition(ColorPickerFormat(stored: nil) == .hex, "hex by default")
        precondition(ColorPickerFormat(stored: "bogus") == .hex, "an unknown stored format is hex")
        precondition(ColorPickerFormat(stored: "swiftUI") == .swiftUI, "a stored format is read back")

        var stored = ""
        for color in [red, teal, red] { stored = ColorPickerHistory.adding(color, to: stored) }
        precondition(stored == "#FF0000 #12ABEF", "newest first, a repeat moves to the front: \(stored)")
        for byte in 1...9 {
            stored = ColorPickerHistory.adding(ColorValue(red: Double(byte) / 255, green: 0, blue: 0), to: stored)
        }
        let colors = ColorPickerHistory.colors(stored)
        precondition(colors.count == ColorPickerHistory.limit, "only the last few are kept")
        precondition(ColorPickerFormat.hex.string(for: colors[0]) == "#090000", "the newest is first")
        precondition(ColorPickerHistory.colors("#FF0000 junk  #00FF00").count == 2, "a damaged entry is skipped")
        print("nc-ColorPicker-format-test: ok")
    }
}
