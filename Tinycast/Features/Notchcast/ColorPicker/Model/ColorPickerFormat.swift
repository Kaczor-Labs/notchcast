import Foundation

/// The notations a picked colour is copied as; a screen pixel is opaque, so none states alpha.
enum ColorPickerFormat: String, CaseIterable, Sendable {
    case hex
    case rgb
    case hsl
    case swiftUI

    static let defaultsKey = "notchcast.colorPicker.format"

    /// An unknown or missing stored value falls back to hex, the issue's default.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .hex
    }

    func string(for color: ColorValue) -> String {
        switch self {
        case .hex: ColorFormat.hex.string(for: color)
        case .hsl: ColorFormat.hsl.string(for: color)
        case .rgb: "rgb(\(Self.byte(color.red)), \(Self.byte(color.green)), \(Self.byte(color.blue)))"
        case .swiftUI:
            "Color(red: \(Self.fraction(color.red)), green: \(Self.fraction(color.green)), "
                + "blue: \(Self.fraction(color.blue)))"
        }
    }

    private static func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }

    /// Three places keep every 8-bit channel exact on the way back, since a step is 1/255.
    private static func fraction(_ value: Double) -> String { String(format: "%.3f", value) }
}

/// The last few picks, newest first, stored as one string of `#RRGGBB` codes.
enum ColorPickerHistory {
    static let defaultsKey = "notchcast.colorPicker.recent"
    static let limit = 5

    static func colors(_ stored: String) -> [ColorValue] {
        stored.split(separator: " ").compactMap { ColorValue.parse(String($0)) }
    }

    /// A repeat moves to the front rather than listing twice.
    static func adding(_ color: ColorValue, to stored: String) -> String {
        let hex = ColorFormat.hex.string(for: color)
        let kept = stored.split(separator: " ").map(String.init).filter { $0 != hex }
        return ([hex] + kept).prefix(limit).joined(separator: " ")
    }
}
