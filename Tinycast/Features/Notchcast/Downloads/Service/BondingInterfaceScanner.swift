import Foundation
import SystemConfiguration

/// Reads the Mac's network interfaces and their IPv4 addresses; it changes no network setting.
enum BondingInterfaceScanner {
    @MainActor
    static func scan() -> [BondingInterface] {
        guard let store = SCDynamicStoreCreate(nil, "Notchcast" as CFString, nil, nil),
              let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]
        else { return [] }
        return interfaces.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let key = "State:/Network/Interface/\(name)/IPv4" as CFString
            let state = SCDynamicStoreCopyValue(store, key) as? [String: Any]
            return BondingInterface(
                bsdName: name,
                isWiFi: SCNetworkInterfaceGetInterfaceType(interface) as String?
                    == kSCNetworkInterfaceTypeIEEE80211 as String,
                port: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "",
                ipv4: state?[kSCPropNetIPv4Addresses as String] as? [String] ?? [])
        }
    }
}
