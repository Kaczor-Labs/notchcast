// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's PeripheralBatterySupport and NotchAccessorySupport: parsing and glyphs.

import Foundation

enum AccessoryKind: String, Sendable {
    case keyboard, mouse, trackpad, audio, device
}

/// One accessory's battery: `percent` is the lowest part, so a low AirPods case alone counts as low.
struct AccessoryBattery: Equatable, Sendable {
    struct Part: Equatable, Sendable {
        enum Name: Sendable { case left, right, batteryCase }

        var name: Name
        var percent: Int
    }

    var name: String
    var percent: Int
    var kind: AccessoryKind
    /// AirPods-style left, right and case levels, when the system reports them.
    var parts: [Part] = []

    var key: String { AccessoryReadings.key(name) }
}

/// Reads the public battery sources: IORegistry HID properties and `system_profiler SPBluetoothDataType -json`.
enum AccessoryReadings {
    static let percentKeys = ["BatteryPercent", "BatteryPercentRemaining", "BatteryLevel", "Battery Level", "Battery"]

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func percent(from value: Any?) -> Int? {
        let raw: Double? = switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String:
            Double(string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
        guard let raw, raw.isFinite, let rounded = Int(exactly: raw.rounded()), (0...100).contains(rounded) else {
            return nil
        }
        return rounded
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty
        else { return nil }
        return string
    }

    /// One IORegistry HID service's properties; nil for a built-in device or one without a name and a level.
    static func hid(_ properties: [String: Any]) -> AccessoryBattery? {
        guard let name = ["Product", "ProductName", "DeviceName"].lazy.compactMap({ text(properties[$0]) }).first,
              let percent = percentKeys.lazy.compactMap({ percent(from: properties[$0]) }).first else { return nil }
        let builtIn = ["Built-In", "BuiltIn", "Builtin", "built-in"].contains { key in
            switch properties[key] {
            case let number as NSNumber: number.boolValue
            case let string as String: ["1", "true", "yes"].contains(string.lowercased())
            default: false
            }
        }
        guard !builtIn else { return nil }
        var usages: [(page: Int, usage: Int)] = []
        if let page = int(properties["PrimaryUsagePage"]) ?? int(properties["DeviceUsagePage"]),
           let usage = int(properties["PrimaryUsage"]) ?? int(properties["DeviceUsage"]) {
            usages.append((page, usage))
        }
        for pair in properties["DeviceUsagePairs"] as? [[String: Any]] ?? [] {
            if let page = int(pair["DeviceUsagePage"]), let usage = int(pair["DeviceUsage"]) {
                usages.append((page, usage))
            }
        }
        return AccessoryBattery(name: name, percent: percent, kind: kind(name: name, usages: usages))
    }

    /// The connected devices `system_profiler SPBluetoothDataType -json` lists with a battery level.
    static func profiler(_ data: Data) -> [AccessoryBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [AccessoryBattery] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    let parts: [AccessoryBattery.Part] = [
                        ("device_batteryLevelLeft", .left), ("device_batteryLevelRight", .right),
                        ("device_batteryLevelCase", .batteryCase),
                    ].compactMap { key, part in percent(from: properties[key]).map { .init(name: part, percent: $0) } }
                    let main = ["device_batteryLevelMain", "device_batteryLevel"].lazy
                        .compactMap { percent(from: properties[$0]) }.first
                    guard let lowest = main ?? parts.map(\.percent).min() else { continue }
                    let named = [name, text(properties["device_minorType"])].compactMap(\.self).joined(separator: " ")
                    devices.append(AccessoryBattery(
                        name: name, percent: lowest, kind: kind(name: named, usages: []), parts: main == nil ? parts : []))
                }
            }
        }
        return devices
    }

    /// One entry per name; a HID reading is fresher than the profiler's, which keeps only AirPods-style parts.
    static func merge(hid: [AccessoryBattery], profiler: [AccessoryBattery]) -> [AccessoryBattery] {
        var byKey: [String: AccessoryBattery] = [:]
        for device in profiler + hid { byKey[device.key] = device }
        return byKey.values.sorted {
            $0.percent != $1.percent ? $0.percent < $1.percent
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func kind(name: String, usages: [(page: Int, usage: Int)]) -> AccessoryKind {
        let name = name.lowercased()
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("trackpad") || name.contains("track pad") { return .trackpad }
        if ["airpods", "headphone", "headset", "buds"].contains(where: name.contains) { return .audio }
        if usages.contains(where: { $0.page == 1 && $0.usage == 2 }) { return .mouse }
        if usages.contains(where: { ($0.page == 1 && $0.usage == 6) || $0.page == 7 }) { return .keyboard }
        if usages.contains(where: { $0.page == 13 && $0.usage == 5 }) { return .trackpad }
        return .device
    }

    static func symbol(_ kind: AccessoryKind, name: String) -> String {
        switch kind {
        case .audio:
            let model = name.lowercased()
            if model.contains("airpods max") { return "airpodsmax" }
            if model.contains("airpods pro") { return "airpodspro" }
            if model.contains("airpods") { return "airpods" }
            return "headphones"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .device: return "dot.radiowaves.left.and.right"
        }
    }

    /// A name says what an accessory is until someone renames it; its Bluetooth class of device still does.
    static func symbol(name: String, majorClass: UInt32, minorClass: UInt32) -> String {
        let named = kind(name: name, usages: [])
        guard named == .device else { return symbol(named, name: name) }
        switch (majorClass, minorClass) {
        case (0x04, 0x04): return "mic"
        case (0x04, 0x05), (0x04, 0x07), (0x04, 0x0A): return "hifispeaker"
        case (0x04, 0x08): return "car"
        case (0x04, 0x0E), (0x04, 0x0F): return "tv"
        case (0x04, 0x12): return "gamecontroller"
        case (0x04, 0x01), (0x04, 0x02), (0x04, 0x06): return symbol(.audio, name: name)
        case (0x05, let minor) where [0x01, 0x02].contains(minor & 0x0F): return "gamecontroller"
        case (0x05, let minor) where minor & 0x0F == 0x03: return "av.remote"
        case (0x05, let minor) where minor & 0x30 == 0x20:
            return symbol(minor & 0x0F == 0x05 ? .trackpad : .mouse, name: name)
        case (0x05, let minor) where minor & 0x10 != 0: return symbol(.keyboard, name: name)
        case (0x06, let minor) where minor & 0x20 != 0: return "printer"
        case (0x07, 0x01): return "applewatch"
        case (0x07, 0x05): return "eyeglasses"
        case (0x08, _): return "gamecontroller"
        default: return symbol(.device, name: name)
        }
    }
}
