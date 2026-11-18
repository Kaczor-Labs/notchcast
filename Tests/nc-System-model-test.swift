// notchcast-sources: Tinycast/Features/Notchcast/System/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-System-model-test: \(message)") }
}

/// Rates, thresholds, the hot state and the page, all from injected samples: no clock, no live read.
@main
struct SystemModelTests {
    static let locale = Locale(identifier: "en_US")
    static let gigabyte: UInt64 = 1_000_000_000

    static func main() {
        rates()
        gaps()
        processes()
        memoryAndInterfaces()
        hotState()
        page()
        print("PASSED")
    }

    static func counters(at: TimeInterval, busy: UInt64, total: UInt64, received: UInt64 = 0, sent: UInt64 = 0,
                         interfaces: Set<String> = ["en0"], processes: [SystemProcessTime] = []) -> SystemCounters {
        SystemCounters(at: at, cpuBusyTicks: busy, cpuTotalTicks: total, processorCount: 8,
                       memoryUsed: 8 * gigabyte, memoryTotal: 16 * gigabyte, memoryPressure: .normal,
                       diskFree: 200 * gigabyte, diskTotal: 500 * gigabyte,
                       network: SystemNetworkCounters(interfaces: interfaces, received: received, sent: sent),
                       processes: processes, thermal: .nominal)
    }

    static func reading(at: TimeInterval = 100, cpu: Double = 0.18, memoryUsed: UInt64 = 8 * gigabyte,
                        pressure: SystemMemoryPressure = .normal, diskFree: UInt64 = 200 * gigabyte,
                        diskTotal: UInt64 = 500 * gigabyte, down: Double? = 1_048_576, up: Double? = 2048,
                        top: [SystemProcessLoad] = [], thermal: SystemThermal = .nominal) -> SystemReading {
        SystemReading(at: at, cpu: cpu, memoryUsed: memoryUsed, memoryTotal: 16 * gigabyte, memoryPressure: pressure,
                      diskFree: diskFree, diskTotal: diskTotal, down: down, up: up, top: top, thermal: thermal)
    }

    static func rates() {
        let first = counters(at: 100, busy: 1000, total: 4000, received: 5_000_000, sent: 1_000_000)
        let second = counters(at: 102, busy: 1500, total: 5000, received: 7_000_000, sent: 1_500_000)
        guard let reading = SystemReading(previous: first, current: second) else { fatalError("two reads make a rate") }
        check(reading.cpu == 0.5, "CPU is busy ticks over all ticks between the reads: \(reading.cpu)")
        check(reading.down == 1_000_000 && reading.up == 250_000, "network is bytes a second over the gap")
        check(reading.memory == 0.5 && reading.diskFreeShare == 0.4, "memory and disk are shares of their totals")
        check(reading.at == 102, "a reading carries the later read's time")

        let moved = counters(at: 102, busy: 1500, total: 5000, received: 9_000_000, interfaces: ["en1"])
        check(SystemReading(previous: first, current: moved)?.down == nil, "a changed interface set is a new baseline")
        let wrapped = counters(at: 102, busy: 1500, total: 5000, received: 10, sent: 10)
        let reset = SystemReading(previous: first, current: wrapped)
        check(reset != nil && reset?.down == nil && reset?.up == nil, "a counter that went back gives no rate")
    }

    static func gaps() {
        let first = counters(at: 100, busy: 1000, total: 4000)
        check(SystemReading(previous: first, current: counters(at: 100.2, busy: 1100, total: 4400)) == nil,
              "reads closer than the minimum gap make no rate")
        check(SystemReading(previous: first, current: counters(at: 161, busy: 9000, total: 90000)) == nil,
              "a gap past the maximum is a pause, not a rate")
        check(SystemReading(previous: first, current: counters(at: 100.5, busy: 1100, total: 4400)) != nil
            && SystemReading(previous: first, current: counters(at: 160, busy: 9000, total: 90000)) != nil,
              "both ends of the allowed gap give a reading")
        check(SystemReading(previous: first, current: counters(at: 102, busy: 1000, total: 4000)) == nil,
              "ticks that did not advance give no rate")
        check(SystemReading(previous: first, current: counters(at: 102, busy: 900, total: 5000)) == nil,
              "busy ticks that went back give no rate")
    }

    static func processes() {
        func time(_ pid: Int32, _ name: String, _ seconds: Double) -> SystemProcessTime {
            SystemProcessTime(pid: pid, name: name, cpuNanoseconds: UInt64(seconds * 1_000_000_000))
        }
        let before = [time(1, "Xcode", 10), time(2, "Helper", 5), time(3, "Helper", 5), time(4, "Old", 50),
                      time(5, "Back", 9), time(6, "Idle", 1), time(7, "A", 0), time(8, "B", 0), time(9, "C", 0),
                      time(10, "D", 0)]
        let after = [time(1, "Xcode", 11.6), time(2, "Helper", 5.8), time(3, "Helper", 6.6), time(4, "New", 60),
                     time(5, "Back", 1), time(6, "Idle", 1.01), time(7, "A", 0.32), time(8, "B", 0.32),
                     time(9, "C", 0.16), time(10, "D", 0.48), time(11, "Fresh", 30)]
        let top = SystemReading.ranked(previous: before, current: after, elapsed: 2, processorCount: 8)
        check(top.map(\.name) == ["Helper", "Xcode", "D", "A", "B"],
              "heaviest first, equal loads by name, five at most: \(top.map(\.name))")
        check(abs(top[0].share - 0.15) < 1e-9 && abs(top[1].share - 0.1) < 1e-9,
              "helpers sum under their name; a share is CPU time over all cores' time: \(top.map(\.share))")
        check(!top.contains { ["New", "Old", "Back", "Fresh", "Idle"].contains($0.name) },
              "a reused pid, time that went back, a process with no earlier read and one under half a percent drop out")
        check(SystemReading.ranked(previous: before, current: [time(1, "Xcode", 99)], elapsed: 2, processorCount: 1)
            .first?.share == 1, "a share never passes the whole Mac")
    }

    static func memoryAndInterfaces() {
        let total = 16 * 1_073_741_824 as UInt64
        check(SystemMemory.used(total: total, pageSize: 16384, internalPages: 500_000, purgeablePages: 100_000,
                                wiredPages: 100_000, compressorPages: 50_000) == 550_000 * 16384,
              "used is app memory less purgeable, plus wired and compressed")
        check(SystemMemory.used(total: total, pageSize: 16384, internalPages: 10, purgeablePages: 20,
                                wiredPages: 5, compressorPages: 0) == 5 * 16384,
              "more purgeable than internal is no app memory")
        check(SystemMemory.used(total: total, pageSize: 16384, internalPages: 9_000_000, purgeablePages: 0,
                                wiredPages: 0, compressorPages: 0) == total, "used never passes what the Mac has")
        check(SystemMemory.used(total: total, pageSize: .max, internalPages: 4, purgeablePages: 0, wiredPages: 0,
                                compressorPages: 0) == total, "an overflow reads as full, not as a wrapped number")
        check(["en0", "en7"].allSatisfy(SystemNetworkCounters.counts), "physical interfaces count")
        check(!["lo0", "utun3", "bridge100", "awdl0", "feth1", ""].contains(where: SystemNetworkCounters.counts),
              "loopback, tunnels, bridges and paired virtual interfaces do not")
        check(SystemMemoryPressure(kernelLevel: 1) == .normal && SystemMemoryPressure(kernelLevel: 2) == .warning
            && SystemMemoryPressure(kernelLevel: 4) == .critical && SystemMemoryPressure(kernelLevel: 3) == .unknown,
              "the kernel's pressure levels map to normal, warning and critical")
    }

    static func hotState() {
        var hot = SystemHotState()
        hot.update(reading())
        check(hot.warnings.isEmpty, "a calm Mac warns of nothing")

        hot.update(reading(at: 100, cpu: 0.95))
        check(hot.warnings.isEmpty, "one busy read is a burst, not a warning")
        hot.update(reading(at: 105, cpu: 0.9))
        check(hot.warnings.isEmpty, "five seconds at the limit is still too short")
        hot.update(reading(at: 112, cpu: 0.95))
        check(hot.warnings == [.cpu], "load held for twelve seconds across reads warns")
        hot.update(reading(at: 127, cpu: 0.89))
        check(hot.warnings.isEmpty, "the warning ends with the first read under the limit")
        hot.update(reading(at: 142, cpu: 0.95))
        check(hot.warnings.isEmpty, "and a new stretch starts from nothing")
        hot.pause()
        hot.update(reading(at: 200, cpu: 0.95))
        check(hot.warnings.isEmpty, "a pause in sampling ends the stretch")

        var state = SystemHotState()
        state.update(reading(thermal: .fair))
        check(state.warnings.isEmpty, "fair thermal pressure is not hot")
        state.update(reading(thermal: .serious))
        check(state.warnings == [.thermal], "serious thermal pressure is")
        state.update(reading(pressure: .warning))
        check(state.warnings.isEmpty, "memory pressure at warning passes")
        state.update(reading(pressure: .critical))
        check(state.warnings == [.memory], "critical memory pressure warns")
        state.update(reading(diskFree: 50 * gigabyte))
        check(state.warnings.isEmpty, "a disk with a tenth free is not almost full")
        state.update(reading(diskFree: 49 * gigabyte))
        check(state.warnings == [.disk], "under a tenth free warns")
        state.update(reading(diskFree: gigabyte / 10, diskTotal: 5 * gigabyte))
        check(state.warnings.isEmpty, "a small volume never warns")

        var all = SystemHotState()
        all.update(reading(at: 100, cpu: 1, pressure: .critical, diskFree: gigabyte, thermal: .critical))
        all.update(reading(at: 115, cpu: 1, pressure: .critical, diskFree: gigabyte, thermal: .critical))
        check(all.warnings == [.thermal, .memory, .cpu, .disk], "warnings come most urgent first")
        check(SystemPage.status(all.warnings)?.label == SystemPage.title(.thermal),
              "the closed island shows the most urgent one")
    }

    static func page() {
        let top = [SystemProcessLoad(name: "Xcode", share: 0.12), SystemProcessLoad(name: "Safari", share: 0.03)]
        let calm = SystemPage.page(reading(top: top), warnings: [], locale: locale)
        check(calm.id == "system" && calm.order == 20 && calm.badge == 0, "the page sits after Agents and Player")
        guard case .meter(let cpu) = calm.blocks[0], case .meter(let memory) = calm.blocks[1],
              case .meter(let disk) = calm.blocks[2], case .row(let network) = calm.blocks[3],
              case .row(let header) = calm.blocks[4], case .row(let first) = calm.blocks[5] else {
            fatalError("nc-System-model-test: four tiles, then the top processes: \(calm.blocks)")
        }
        check(cpu.fraction == 0.18 && cpu.value == "18%", "the CPU tile reads its share: \(cpu.value)")
        check(memory.fraction == 0.5 && disk.fraction == 0.6, "memory and disk tiles fill by what is used")
        check(disk.value.contains(SystemPage.bytes(200 * gigabyte, style: .file, locale: locale)),
              "the disk tile says what is free: \(disk.value)")
        check(network.trailing?.contains("↓") == true && network.trailing?.contains("↑") == true && network.id == nil,
              "the network tile reads down and up: \(network.trailing ?? "")")
        check(header.symbol != nil && first.title == "Xcode" && first.trailing == "12%" && calm.blocks.count == 7,
              "top processes follow their header, heaviest first")
        check(calm.line.symbol == "cpu" && calm.line.text.hasSuffix("50%") && calm.line.detail?.hasSuffix("18%") == true,
              "Home reads the busier of CPU and memory, the other beside it: \(calm.line)")
        let busy = SystemPage.line(reading(cpu: 0.8), warnings: [], locale: locale)
        check(busy.text.hasSuffix("80%") && busy.detail?.hasSuffix("50%") == true, "a busier CPU leads Home")
        check(SystemPage.status([]) == nil, "a calm Mac puts nothing in the closed island")

        let quiet = SystemPage.page(reading(down: nil, up: nil), warnings: [], locale: locale)
        check(quiet.blocks.count == 4, "no process over half a percent leaves no process list")
        guard case .row(let offline) = quiet.blocks[3] else { fatalError("nc-System-model-test: network row") }
        check(offline.trailing == "↓ –  ↑ –", "no rate reads as a dash, never as zero")

        let hot = SystemPage.page(reading(cpu: 0.97), warnings: [.cpu, .disk], locale: locale)
        guard case .row(let warning) = hot.blocks[0], case .row(let second) = hot.blocks[1] else {
            fatalError("nc-System-model-test: warnings lead the page")
        }
        check(warning.symbol == SystemPage.warningSymbol && warning.title == SystemPage.title(.cpu)
            && warning.detail == SystemPage.detail(.cpu) && second.title == SystemPage.title(.disk),
              "each warning is a glyph and words, never colour alone")
        check(hot.line.symbol == SystemPage.warningSymbol && hot.line.text == SystemPage.title(.cpu)
            && hot.line.detail?.hasSuffix("97%") == true, "Home leads with the warning")
        for warning in SystemWarning.allCases {
            let status = SystemPage.status([warning])
            check(status?.symbol == SystemPage.warningSymbol && (1...4).contains(status?.text?.count ?? 0)
                && status?.label == SystemPage.title(warning) && status?.id == SystemPage.statusID,
                  "the closed island gets a glyph and a word of four characters at most: \(String(describing: status))")
        }
    }
}
