import Foundation

/// What holds keyboard focus in Finder, read from the focused element up to its window.
enum FinderToolsFocus: Sendable, Equatable {
    case fileList
    /// A rename or search field: ⌘X and ⌘V stay text cut and paste.
    case text
    /// A menu, dialog or sheet: the original keys go through and the pending cut is dropped.
    case blocked

    struct Element: Sendable, Equatable {
        let role: String
        var subrole: String?
    }

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let blockingRoles: Set<String> = ["AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXSheet"]
    static let blockingSubroles: Set<String> = ["AXDialog", "AXSystemDialog"]

    /// `chain` runs from the focused element outward; nil or empty means the read failed.
    init(chain: [Element]?) {
        guard let chain, let focused = chain.first else { self = .blocked; return }
        if Self.textRoles.contains(focused.role) {
            self = .text
        } else if chain.contains(where: {
            Self.blockingRoles.contains($0.role) || $0.subrole.map(Self.blockingSubroles.contains) == true
        }) {
            self = .blocked
        } else {
            self = .fileList
        }
    }
}
