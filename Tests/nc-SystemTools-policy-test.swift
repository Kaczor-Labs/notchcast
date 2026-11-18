// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/*.swift
import Foundation

// Pure text and numbers only: no process is read, no file under /etc is touched, no tool runs.
@main
enum SystemToolsPolicyTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        pamFile()
        processList()
        networkQuality()
        networkInfo()
        print("\(checks) system tools policy checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    typealias Pam = SudoTouchIDPolicy
    static let template = """
        # sudo_local: local config file which survives system update and is included for sudo
        # uncomment following line to enable Touch ID for sudo
        #auth       sufficient     pam_tid.so

        """
    static let sudo = """
        # sudo: auth account password session
        auth       include        sudo_local
        auth       sufficient     pam_smartcard.so
        auth       required       pam_opendirectory.so

        """

    static func pamFile() {
        check("sudo that includes sudo_local is supported", Pam.includesLocal(sudo: sudo))
        check("sudo without the include is not",
              !Pam.includesLocal(sudo: sudo.replacingOccurrences(of: "auth       include        sudo_local", with: "")))
        check("a commented-out rule is off", !Pam.isEnabled(local: template))
        check("no file is off", !Pam.isEnabled(local: nil))

        let fresh = Pam.change(nil, enabled: true)
        check("enabling with no file writes just the rule", fresh == Pam.rule + "\n")
        check("disabling with no file writes nothing", Pam.change(nil, enabled: false) == nil)

        guard let on = Pam.change(template, enabled: true) else { return check("enabling the template changes it", false) }
        check("enabling keeps every template line in place", on.hasPrefix(template))
        check("enabling appends the rule once", on == template + Pam.rule + "\n")
        check("the result reads as on", Pam.isEnabled(local: on))
        check("enabling twice writes nothing the second time", Pam.change(on, enabled: true) == nil)

        guard let off = Pam.change(on, enabled: false) else { return check("disabling changes it", false) }
        check("disabling restores the template byte for byte", off == template)
        check("disabling twice writes nothing", Pam.change(off, enabled: false) == nil)

        let reattach = "auth     optional     /opt/homebrew/lib/pam/pam_reattach.so"
        let other = reattach + "\n" + "auth       sufficient     pam_tid.so ignore_ssh  # mine\n" + "account required pam_x.so"
        check("a rule with options counts as on", Pam.isEnabled(local: other))
        let cleaned = Pam.change(other, enabled: false)
        check("disabling removes only the rule lines",
              cleaned == reattach + "\n" + "account required pam_x.so")
        let noNewline = "auth     optional     pam_reattach.so"
        check("a file without a final newline gets one before the rule",
              Pam.change(noNewline, enabled: true) == noNewline + "\n" + Pam.rule + "\n")
        check("the rule lands after pam_reattach, which must run first",
              Pam.change(noNewline, enabled: true)?.components(separatedBy: "\n").firstIndex(of: Pam.rule) == 1)
        check("auth required pam_tid.so is not our rule", !Pam.isEnabled(local: "auth required pam_tid.so\n"))
        let spaced = "  auth\tsufficient\tpam_tid.so\n"
        check("tabs and indentation still read as the rule", Pam.isEnabled(local: spaced))
    }

    static func sample(
        _ pid: Int32, _ name: String, cpu: UInt64 = 0, memory: UInt64 = 0, start: UInt64 = 1, path: String = ""
    ) -> ProcessSample {
        ProcessSample(pid: pid, start: start, name: name, path: path, isApp: false, cpuNanoseconds: cpu, memoryBytes: memory)
    }

    static func processList() {
        let second: UInt64 = 1_000_000_000
        let before = [sample(10, "Safari", cpu: second), sample(11, "worker", cpu: 4 * second), sample(12, "old", start: 1)]
        let after = [
            sample(10, "Safari", cpu: second + second / 2, memory: 900), sample(11, "worker", cpu: 9 * second, memory: 5),
            sample(12, "old", cpu: 9 * second, start: 2), sample(13, "new", cpu: 3 * second),
            sample(99, "Notchcast Dev"), sample(1, "launchd"), sample(20, "LoginWindow"),
            sample(21, "ws", path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
            sample(4242, "Notchcast"),
        ]
        let rows = ProcessListPolicy.rows(
            previous: before, current: after, elapsedNanoseconds: second, ownPID: 99, processorCount: 2)
        let cpu = Dictionary(uniqueKeysWithValues: rows.map { ($0.sample.pid, $0.cpuPercent) })
        check("CPU is the time used over the interval, shared by every core", cpu[10] == 25)
        check("CPU never passes 100 %", cpu[11] == 100)
        check("a reused pid starts again at 0 %", cpu[12] == 0)
        check("a process new since the last reading reads 0 %", cpu[13] == 0)
        check("Notchcast itself is never offered", cpu[99] == nil)
        check("another Notchcast copy is never offered", cpu[4242] == nil)
        check("pid 1 is never offered", cpu[1] == nil)
        check("loginwindow is never offered, whatever its case", cpu[20] == nil)
        check("WindowServer is never offered by its path", cpu[21] == nil)
        check("the first reading has no CPU yet",
              ProcessListPolicy.rows(previous: [], current: after, elapsedNanoseconds: 0, ownPID: 99, processorCount: 2)
                  .allSatisfy { $0.cpuPercent == 0 })

        check("mach ticks convert to nanoseconds",
              ProcessListPolicy.nanoseconds(ticks: 3_000, numerator: 125, denominator: 3) == 125_000)
        check("a zero timebase reads nothing", ProcessListPolicy.nanoseconds(ticks: 1, numerator: 1, denominator: 0) == nil)
        check("an overflowing conversion reads nothing",
              ProcessListPolicy.nanoseconds(ticks: .max, numerator: 125, denominator: 3) == nil)

        func names(_ query: String, _ list: [ProcessRow]) -> [String] {
            ProcessListPolicy.arrange(list, query: query).map(\.sample.name)
        }
        func row(_ name: String, cpu: Double, pid: Int32) -> ProcessRow {
            ProcessRow(sample: sample(pid, name), cpuPercent: cpu)
        }
        let list = [
            row("Safari", cpu: 10, pid: 2), row("MobileSafari", cpu: 90, pid: 1), row("Helper", cpu: 1, pid: 30),
            row("zsh", cpu: 0, pid: 5), row("bash", cpu: 0, pid: 4),
        ]
        check("no query lists busiest first, ties by pid",
              names("", list) == ["MobileSafari", "Safari", "Helper", "bash", "zsh"])
        check("a blank query is no query", names("  ", list) == names("", list))
        check("a query keeps names containing it, busiest first", names("saf", list) == ["MobileSafari", "Safari"])
        check("matching ignores case", names("SAFARI", list) == ["MobileSafari", "Safari"])
        check("a query can be the pid", names("30", list) == ["Helper"])
        check("no match lists nothing", names("xyz", list).isEmpty)

        let detail = ProcessListPolicy.detail(ProcessRow(sample: sample(1, "x", memory: 640 * 1_048_576), cpuPercent: 12.4))
        let percent = 12.4.formatted(.number.precision(.fractionLength(1)))
        check("the row detail states CPU and memory (\(detail))", detail.hasPrefix("\(percent)%") && detail.contains("MB"))
    }

    static func networkQuality() {
        let fixture = Data("""
            {"base_rtt": 21.5, "dl_flows": 12, "dl_throughput": 278390616, "ul_throughput": 21434567,
             "responsiveness": 1234.4, "interface_name": "en0", "il_h2_req_resp": [12, 13]}
            """.utf8)
        guard let result = try? NetworkQualityResult.parse(fixture) else { return check("a full run parses", false) }
        check("download is bits per second", result.downloadBitsPerSecond == 278_390_616)
        check("upload is bits per second", result.uploadBitsPerSecond == 21_434_567)
        check("responsiveness is RPM", result.responsivenessRPM == 1234.4)
        let summary = result.summary
        let tenths = 21.4.formatted(.number.precision(.fractionLength(1)))
        check("the summary states both speeds in Mbps (\(summary))",
              summary.contains("278 Mbps") && summary.contains("\(tenths) Mbps"))
        check("the summary ends with RPM (\(summary))", summary.hasSuffix(" RPM") && summary.contains("234"))
        check("download comes first (\(summary))", summary.hasPrefix("↓"))

        let noRPM = try? NetworkQualityResult.parse(Data(#"{"dl_throughput": 5e6, "ul_throughput": 1e6}"#.utf8))
        check("a run without responsiveness still parses, with no RPM", noRPM?.summary.contains("RPM") == false)
        let five = 5.0.formatted(.number.precision(.fractionLength(1)))
        check("under 100 Mbps keeps one decimal", noRPM?.summary.contains("↓ \(five) Mbps") == true)

        func failure(_ text: String) -> NetworkQualityResult.Failure? {
            do {
                _ = try NetworkQualityResult.parse(Data(text.utf8))
                return nil
            } catch {
                return error
            }
        }
        check("the tool's own error is reported with its code",
              failure(#"{"error_code": -1009, "error_domain": "NSURLErrorDomain"}"#)
                  == .tool(domain: "NSURLErrorDomain", code: -1009))
        check("an error wins over partial numbers",
              failure(#"{"dl_throughput": 5, "ul_throughput": 1, "error_code": 7}"#) == .tool(domain: "", code: 7))
        check("output that is not JSON is unreadable", failure("Downlink capacity: 278 Mbps") == .unreadable)
        check("a run missing upload is unreadable", failure(#"{"dl_throughput": 5}"#) == .unreadable)
        check("an empty run is unreadable", failure("") == .unreadable)
    }

    static func networkInfo() {
        let ports = """
            Hardware Port: Ethernet
            Device: en7
            Ethernet Address: aa:bb:cc:dd:ee:ff

            Hardware Port: Wi-Fi
            Device: en1
            Ethernet Address: aa:bb:cc:dd:ee:00
            """
        check("the Wi-Fi device is the one under its port", NetworkInfoPolicy.wifiDevice(hardwarePorts: ports) == "en1")
        check("no Wi-Fi port, no device",
              NetworkInfoPolicy.wifiDevice(hardwarePorts: "Hardware Port: Ethernet\nDevice: en0") == nil)
        let preferred = "Preferred networks on en1:\n\tHome\n\tOffice 5G\n\tHome\n\t \n"
        check("saved networks keep the system's order, once each",
              NetworkInfoPolicy.savedNetworks(preferred: preferred) == ["Home", "Office 5G"])
        check("an error line lists nothing",
              NetworkInfoPolicy.savedNetworks(preferred: "en1 is not a Wi-Fi interface.\n").isEmpty)
        check("network search ignores case", NetworkInfoPolicy.filter(["Home", "Office 5G"], query: "office") == ["Office 5G"])
        check("a blank search lists all", NetworkInfoPolicy.filter(["Home", "Office"], query: " ").count == 2)

        func address(_ text: String) -> String? { NetworkInfoPolicy.publicAddress(from: Data(text.utf8)) }
        check("an IPv4 reply is read", address("203.0.113.7\n") == "203.0.113.7")
        check("an IPv6 reply is read", address("2001:db8::1") == "2001:db8::1")
        check("an HTML page is not an address", address("<html>blocked</html>") == nil)
        check("an octet over 255 is not an address", address("203.0.113.700") == nil)
        check("three octets are not an address", address("10.0.1") == nil)
        check("a long reply is refused", NetworkInfoPolicy.publicAddress(from: Data(repeating: 0x31, count: 65)) == nil)

        check("an up IPv4 Wi-Fi interface counts",
              NetworkAddressPolicy.includes(name: "en0", isUp: true, isRunning: true, isIPv4: true))
        check("loopback never counts", !NetworkAddressPolicy.includes(name: "lo0", isUp: true, isRunning: true, isIPv4: true))
        check("a VPN tunnel never counts",
              !NetworkAddressPolicy.includes(name: "utun3", isUp: true, isRunning: true, isIPv4: true))
        check("a down interface never counts",
              !NetworkAddressPolicy.includes(name: "en0", isUp: false, isRunning: true, isIPv4: true))
        check("IPv6 is left out", !NetworkAddressPolicy.includes(name: "en0", isUp: true, isRunning: true, isIPv4: false))
        let arranged = NetworkAddressPolicy.arrange([
            LocalAddress(ip: "192.168.1.5", connection: "Wi-Fi"), LocalAddress(ip: "10.0.0.2", connection: nil),
            LocalAddress(ip: "192.168.1.5", connection: "Wi-Fi"),
        ])
        check("addresses are sorted, once each", arranged.map(\.ip) == ["10.0.0.2", "192.168.1.5"])
        check("an address is labelled by its connection", arranged.last?.label == "192.168.1.5 (Wi-Fi)")
    }
}
