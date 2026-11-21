import Foundation

/// Connected accessories with a battery as the island's Accessories page: one card each, lowest first.
enum AccessoryPage {
    static let id = "accessories"
    static let symbol = "battery.75percent"
    /// After System (20), before Day (30) (island-shell "Pages").
    static let order = 25

    /// Nil while no connected accessory reports a level, so the island shows no empty tab.
    static func page(_ devices: [AccessoryBattery]) -> IslandPage? {
        guard let lowest = devices.first else { return nil }
        let line = IslandPageLine(
            symbol: AccessoryReadings.symbol(lowest.kind, name: lowest.name),
            text: String(localized: "\(lowest.name): \(lowest.percent)%", table: "NotchcastAccessories"),
            detail: devices.count > 1
                ? String(localized: "\(devices.count) accessories", table: "NotchcastAccessories") : nil)
        let group = IslandCardGroup(title: String(localized: "Connected", table: "NotchcastAccessories"),
                                    cards: devices.map(card))
        return IslandPage(id: id, title: String(localized: "Accessories", table: "NotchcastAccessories"),
                          symbol: symbol, order: order, line: line, blocks: [.cards(group)])
    }

    static func card(_ device: AccessoryBattery) -> IslandCard {
        let meters = device.parts.isEmpty
            ? [meter(String(localized: "Battery", table: "NotchcastAccessories"), device.percent)]
            : device.parts.map { meter(label($0.name), $0.percent) }
        let levels = meters.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        return IslandCard(title: device.name, body: .meters(meters), spoken: "\(device.name), \(levels)")
    }

    private static func meter(_ label: String, _ percent: Int) -> IslandCardMeter {
        IslandCardMeter(label: label, value: "\(percent)%", fraction: Double(percent) / 100,
                        warning: percent <= AccessoryLowWatch.threshold)
    }

    private static func label(_ part: AccessoryBattery.Part.Name) -> String {
        switch part {
        case .left: String(localized: "Left", table: "NotchcastAccessories")
        case .right: String(localized: "Right", table: "NotchcastAccessories")
        case .batteryCase: String(localized: "Case", table: "NotchcastAccessories")
        }
    }
}
