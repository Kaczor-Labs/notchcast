// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/BondingPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/BondingState.swift
import Foundation

/// #925, #1183: which interfaces qualify, one switch for every size, aria2c's flag, and how long the iPhone mark lasts.
@main
@MainActor
struct DownloadsBondingTest {
    static let wifi = BondingInterface(bsdName: "en0", isWiFi: true, port: "Wi-Fi", ipv4: ["192.168.1.5"])
    static let iPhone = BondingInterface(bsdName: "en7", isWiFi: false, port: "iPhone USB", ipv4: ["172.20.10.2"])
    static let both = BondedPair(wifi: "en0", iPhone: "en7")

    static func main() {
        addresses()
        filtering()
        enabled()
        marks()
        print("Downloads bonding: IPv4 and name filtering, the switch alone decides, aria2c flag, mark only while both are up")
    }

    private static func addresses() {
        for address in ["192.168.1.5", "172.20.10.2", "10.0.0.1", "223.255.255.254", "1.1.1.1", "169.253.0.1"] {
            expect(BondingPolicy.isUsableIPv4(address), "\(address) is usable")
        }
        for address in ["0.0.0.0", "127.0.0.1", "169.254.12.9", "224.0.0.1", "239.1.2.3", "255.255.255.255",
                        "", "1.2.3", "1.2.3.4.5", "1.2.3.256", "a.b.c.d", "1..2.3", "+1.2.3.4", "fe80::1"] {
            expect(!BondingPolicy.isUsableIPv4(address), "\(address) is refused")
        }
    }

    private static func filtering() {
        expect(BondingPolicy.pair(in: [iPhone, wifi]) == both, "Wi-Fi and the USB iPhone pair up, in any order")
        expect(both.arguments == ["--multiple-interface=en0,en7"], "aria2c gets Wi-Fi first, then the iPhone")
        expect(BondingPolicy.pair(in: [wifi]) == nil && BondingPolicy.pair(in: [iPhone]) == nil
               && BondingPolicy.pair(in: []) == nil, "one interface alone never bonds")

        func phone(_ change: (inout BondingInterface) -> Void) -> BondedPair? {
            var phone = iPhone
            change(&phone)
            return BondingPolicy.pair(in: [wifi, phone])
        }
        expect(phone { $0.port = "iphone usb 2" } == both, "the port name matches in any case")
        for port in ["iPhone", "USB 10/100/1000 LAN", "iPad USB", "Thunderbolt Bridge", ""] {
            expect(phone { $0.port = port } == nil, "port \(port) is not a USB iPhone")
        }
        for addresses in [[], ["0.0.0.0"], ["169.254.3.4"], ["127.0.0.1"], ["224.0.0.5"]] {
            expect(phone { $0.ipv4 = addresses } == nil, "an iPhone with \(addresses) has no usable IPv4")
        }
        expect(phone { $0.ipv4 = ["169.254.3.4", "172.20.10.2"] } == both, "one usable address is enough")
        for name in ["", "en 7", "en7,en0", "en7;x", "en-7", "énɛ7", "--en7", "en７"] {
            expect(phone { $0.bsdName = name } == nil, "BSD name \(name) never reaches aria2c")
        }
        var hotspot = wifi
        hotspot.ipv4 = ["169.254.1.1"]
        expect(BondingPolicy.pair(in: [hotspot, iPhone]) == nil, "Wi-Fi without a usable address does not bond")
        var second = wifi
        second.bsdName = "en1"
        expect(BondingPolicy.pair(in: [second, iPhone, wifi]) == both, "two candidates: the lowest BSD name wins")
        var wirelessPhone = iPhone
        wirelessPhone.isWiFi = true
        expect(BondingPolicy.pair(in: [wirelessPhone]) == nil, "one interface is never both halves")
    }

    private static func enabled() {
        expect(BondingPolicy.pair(enabled: true, interfaces: [wifi, iPhone]) == both, "on and both up: it bonds")
        expect(BondingPolicy.pair(enabled: false, interfaces: [wifi, iPhone]) == nil, "off by default: nothing bonds")
        expect(BondingPolicy.pair(enabled: true, interfaces: [wifi]) == nil, "no iPhone: the job runs normally")
        expect(BondingPolicy.pair(enabled: true, interfaces: [iPhone]) == nil, "no Wi-Fi: the job runs normally")
    }

    private static func marks() {
        let mac = Mac()
        let state = BondingState(interfaces: {
            mac.reads += 1
            return mac.interfaces
        }, now: { mac.now })
        expect(!state.torrentsBonded, "no session started yet: no mark")
        expect(state.startTorrents(enabled: false).isEmpty && !state.torrentsBonded, "option off: no flag, no mark")
        expect(state.startTorrents(enabled: true) == ["--multiple-interface=en0,en7"], "the session gets both")
        mac.reads = 0
        expect(state.torrentsBonded && state.torrentsBonded && mac.reads == 1, "one look serves the same second")

        mac.interfaces = [wifi]
        expect(state.torrentsBonded, "still the same second")
        mac.now += 1
        expect(!state.torrentsBonded, "iPhone unplugged: the mark is gone")
        mac.interfaces = [wifi, iPhone]
        mac.now += 1
        expect(state.torrentsBonded, "plugged back in while aria2c still runs on both: the mark returns")
        var idle = iPhone
        idle.ipv4 = []
        mac.interfaces = [wifi, idle]
        mac.now += 1
        expect(!state.torrentsBonded, "hotspot off, cable in: no IPv4, no mark")
        mac.interfaces = [wifi]
        expect(state.startTorrents(enabled: true).isEmpty, "a session started on Wi-Fi alone gets no flag")
        mac.interfaces = [wifi, iPhone]
        mac.now += 1
        expect(!state.torrentsBonded, "and shows no mark when the iPhone arrives later")

        func job(_ id: String, _ state: DownloadState) -> DownloadJob {
            DownloadJob(id: id, kind: "video", source: "https://example.com/" + id, title: id, state: state,
                        created: mac.now)
        }
        expect(state.startDownload("off", enabled: false).isEmpty, "option off: no flag")
        expect(state.startDownload("on", enabled: true) == ["--multiple-interface=en0,en7"],
               "option on: both interfaces, whatever the size")
        expect(state.downloadsBonded([job("off", .running), job("on", .running)]), "the bonded job shows the mark")
        expect(!state.downloadsBonded([job("off", .running), job("on", .done)]), "the other one alone does not")
        expect(!state.downloadsBonded([job("on", .running)]), "and a finished job is forgotten")
        _ = state.startDownload("big", enabled: true)
        state.endDownload("big")
        expect(!state.downloadsBonded([job("big", .running)]), "a retry without aria2c drops the mark")
        _ = state.startDownload("big", enabled: true)
        mac.interfaces = [wifi]
        mac.now += 1
        expect(!state.downloadsBonded([job("big", .running)]), "unplugged mid-download: the mark is gone")
    }

    /// The Mac's interfaces and clock, moved by hand.
    @MainActor private final class Mac {
        var interfaces = [wifi, iPhone]
        var now = Date(timeIntervalSince1970: 1_000)
        var reads = 0
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
}
