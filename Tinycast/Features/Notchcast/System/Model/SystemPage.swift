import Foundation

/// The System page (#977) as island values: warnings, four tiles, top processes, its Home line and status.
enum SystemPage {
    static let id = "system"
    /// After Agents (0) and Player (10), before Day (30), as decision 946-11 orders them.
    static let order = 20
    static let statusID = "system.hot"
    static let warningSymbol = "exclamationmark.triangle.fill"

    static func page(_ reading: SystemReading, warnings: [SystemWarning], locale: Locale) -> IslandPage {
        let rows = warnings.map {
            IslandPageBlock.row(IslandPageRow(symbol: warningSymbol, title: title($0), detail: detail($0)))
        }
        return IslandPage(id: id, title: String(localized: "System", table: "NotchcastSystem"), symbol: "cpu",
                          order: order, line: line(reading, warnings: warnings, locale: locale),
                          blocks: rows + tiles(reading, locale: locale) + processes(reading.top, locale: locale))
    }

    /// The closed island's glyph and short word while something runs hot, nil otherwise.
    static func status(_ warnings: [SystemWarning]) -> IslandStatus? {
        warnings.first.map { IslandStatus(id: statusID, symbol: warningSymbol, text: word($0), label: title($0)) }
    }

    /// The warning that holds, else the busier of CPU and memory, with the other as its detail.
    static func line(_ reading: SystemReading, warnings: [SystemWarning], locale: Locale) -> IslandPageLine {
        let cpu = String(localized: "CPU", table: "NotchcastSystem") + " " + percent(reading.cpu, locale: locale)
        let memory = String(localized: "Memory", table: "NotchcastSystem") + " "
            + percent(reading.memory, locale: locale)
        let busiest = reading.cpu >= reading.memory ? (cpu, memory) : (memory, cpu)
        if let warning = warnings.first {
            return IslandPageLine(symbol: warningSymbol, text: title(warning), detail: busiest.0)
        }
        return IslandPageLine(symbol: "cpu", text: busiest.0, detail: busiest.1)
    }

    static func tiles(_ reading: SystemReading, locale: Locale) -> [IslandPageBlock] {
        let used = bytes(reading.memoryUsed, style: .memory, locale: locale)
        let total = bytes(reading.memoryTotal, style: .memory, locale: locale)
        let free = bytes(reading.diskFree, style: .file, locale: locale)
        let down = reading.down.map { speed($0, locale: locale) } ?? "–"
        let up = reading.up.map { speed($0, locale: locale) } ?? "–"
        return [
            .meter(IslandPageMeter(label: String(localized: "CPU", table: "NotchcastSystem"), fraction: reading.cpu,
                                   value: percent(reading.cpu, locale: locale))),
            .meter(IslandPageMeter(label: String(localized: "Memory", table: "NotchcastSystem"),
                                   fraction: reading.memory,
                                   value: String(localized: "\(used) of \(total)", table: "NotchcastSystem"))),
            .meter(IslandPageMeter(label: String(localized: "Disk", table: "NotchcastSystem"),
                                   fraction: 1 - reading.diskFreeShare,
                                   value: String(localized: "\(free) free", table: "NotchcastSystem"))),
            .row(IslandPageRow(symbol: "network", title: String(localized: "Network", table: "NotchcastSystem"),
                               trailing: "↓ \(down)  ↑ \(up)")),
        ]
    }

    static func processes(_ top: [SystemProcessLoad], locale: Locale) -> [IslandPageBlock] {
        guard !top.isEmpty else { return [] }
        let header = IslandPageRow(symbol: "chart.bar.xaxis",
                                   title: String(localized: "Top Processes", table: "NotchcastSystem"))
        return [.row(header)] + top.map {
            IslandPageBlock.row(IslandPageRow(title: $0.name, trailing: percent($0.share, locale: locale)))
        }
    }

    static func title(_ warning: SystemWarning) -> String {
        switch warning {
        case .thermal: String(localized: "Running Hot", table: "NotchcastSystem")
        case .memory: String(localized: "Memory Pressure", table: "NotchcastSystem")
        case .cpu: String(localized: "CPU High", table: "NotchcastSystem")
        case .disk: String(localized: "Disk Almost Full", table: "NotchcastSystem")
        }
    }

    static func detail(_ warning: SystemWarning) -> String {
        switch warning {
        case .thermal: String(localized: "The Mac is slowing down to cool off.", table: "NotchcastSystem")
        case .memory: String(localized: "Memory is critically low. Quit apps you don’t need.", table: "NotchcastSystem")
        case .cpu: String(localized: "CPU load has stayed very high.", table: "NotchcastSystem")
        case .disk: String(localized: "The startup disk is almost out of space.", table: "NotchcastSystem")
        }
    }

    /// Four characters at most: the closed island shows no more beside its glyph.
    static func word(_ warning: SystemWarning) -> String {
        switch warning {
        case .thermal: String(localized: "Hot", table: "NotchcastSystem")
        case .memory: String(localized: "RAM", table: "NotchcastSystem")
        case .cpu: String(localized: "CPU", table: "NotchcastSystem")
        case .disk: String(localized: "Disk", table: "NotchcastSystem")
        }
    }

    static func percent(_ share: Double, locale: Locale) -> String {
        min(max(share, 0), 1).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    static func bytes(_ count: UInt64, style: ByteCountFormatStyle.Style, locale: Locale) -> String {
        Int64(clamping: count).formatted(.byteCount(style: style, spellsOutZero: false).locale(locale))
    }

    static func speed(_ bytesPerSecond: Double, locale: Locale) -> String {
        let count = bytes(UInt64(exactly: max(bytesPerSecond, 0).rounded()) ?? 0, style: .memory, locale: locale)
        return String(localized: "\(count)/s", table: "NotchcastSystem")
    }
}
