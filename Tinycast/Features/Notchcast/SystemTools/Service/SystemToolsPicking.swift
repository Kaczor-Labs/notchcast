import Foundation
import Observation

/// One row a picker lists; `bundlePath` draws an app's icon, else `symbol`.
struct SystemToolsPickerRow: Equatable {
    let title: String
    var detail: String?
    var bundlePath: String?
    var symbol: String
}

/// What the shared picker panel shows and does; Kill Process and the Wi-Fi password each have one.
@MainActor
protocol SystemToolsPicking: AnyObject {
    var title: String { get }
    var header: String { get }
    var placeholder: String { get }
    var pickerRows: [SystemToolsPickerRow] { get }
    var query: String { get set }
    var selectedIndex: Int { get set }
    /// Nil for a list read once.
    var refreshInterval: Duration? { get }
    func refresh() async
    /// The panel has closed by now; `option` is ⌥ held.
    func activate(_ index: Int, option: Bool)
}

/// The saved Wi-Fi networks, the fallback list; choosing one asks macOS for its password.
@MainActor
@Observable
final class WiFiNetworkSession: SystemToolsPicking {
    static let symbol = "wifi"

    private(set) var networks: [String] = []
    var query = "" { didSet { networks = NetworkInfoPolicy.filter(saved, query: query) } }
    var selectedIndex = 0
    @ObservationIgnored private let saved: [String]
    @ObservationIgnored private let locationOff: Bool
    @ObservationIgnored private let choose: @MainActor (String) -> Void

    init(saved: [String], locationOff: Bool, choose: @escaping @MainActor (String) -> Void) {
        self.saved = saved
        self.locationOff = locationOff
        networks = saved
        self.choose = choose
    }

    var title: String { String(localized: "Copy Wi-Fi Password", table: "NotchcastSystemTools") }
    var header: String {
        locationOff
            ? String(localized: "Location Is Off, So Choose a Network", table: "NotchcastSystemTools")
            : String(localized: "↩ Copy Password", table: "NotchcastSystemTools")
    }
    var placeholder: String { String(localized: "Search Wi-Fi Networks…", table: "NotchcastSystemTools") }
    var pickerRows: [SystemToolsPickerRow] { networks.map { SystemToolsPickerRow(title: $0, symbol: Self.symbol) } }
    var refreshInterval: Duration? { nil }

    func refresh() async {}

    func activate(_ index: Int, option: Bool) {
        guard networks.indices.contains(index) else { return }
        choose(networks[index])
    }
}
