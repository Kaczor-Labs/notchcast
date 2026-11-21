import Foundation

struct NotchcastSettingsLayout {
    struct Group: Identifiable {
        let category: NotchcastCategory
        let switches: [NotchcastSwitch]
        let details: [Detail]

        var id: NotchcastCategory { category }
    }

    struct Detail: Identifiable {
        let item: NotchcastSwitch
        let dependents: [NotchcastSwitch]
        let hasRows: Bool
        let hasCommands: Bool

        var id: String { item.id }
        var hasOptions: Bool { hasRows || !dependents.isEmpty }
    }

    private let switches: [NotchcastSwitch]
    private let byID: [String: NotchcastSwitch]

    init(switches: [NotchcastSwitch]) {
        self.switches = switches
        byID = Dictionary(switches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func groups(
        in pane: NotchcastPane, isEnabled: (String) -> Bool, withCommands: Set<String>, withRows: Set<String>
    ) -> [Group] {
        func isVisible(_ item: NotchcastSwitch) -> Bool {
            hasValidDependencies(item, visiting: [])
                && item.dependencies.allSatisfy(isEnabled)
                && (item.listedWhenAnyEnabled.isEmpty || item.listedWhenAnyEnabled.contains {
                    byID[$0] != nil && isEnabled($0)
                })
        }

        func details(for item: NotchcastSwitch) -> [Detail] {
            guard isEnabled(item.id) else { return [] }
            let children = switches.filter { $0.dependencies.first == item.id && isVisible($0) }
            let detail = Detail(item: item, dependents: children,
                                hasRows: withRows.contains(item.id), hasCommands: withCommands.contains(item.id))
            return detail.hasOptions || detail.hasCommands ? [detail] + children.flatMap(details) : []
        }

        return pane.categories.compactMap { category in
            let listed = switches.filter { $0.category == category && $0.dependencies.isEmpty && isVisible($0) }
            guard !listed.isEmpty else { return nil }
            return Group(category: category, switches: listed, details: listed.flatMap(details))
        }
    }

    func listedOwners(of item: NotchcastSwitch) -> [String] {
        guard let owner = root(of: item) else { return [] }
        guard !owner.listedWhenAnyEnabled.isEmpty else { return [owner.id] }
        return owner.listedWhenAnyEnabled.compactMap { id in
            guard let item = byID[id], let alternative = root(of: item),
                  alternative.listedWhenAnyEnabled.isEmpty else { return nil }
            return alternative.id
        }
    }

    private func root(of item: NotchcastSwitch) -> NotchcastSwitch? {
        guard hasValidDependencies(item, visiting: []) else { return nil }
        var root = item
        while let parent = root.dependencies.first.flatMap({ byID[$0] }) { root = parent }
        return root
    }

    private func hasValidDependencies(_ item: NotchcastSwitch, visiting: Set<String>) -> Bool {
        guard !visiting.contains(item.id) else { return false }
        let path = visiting.union([item.id])
        return item.dependencies.allSatisfy { id in
            guard let parent = byID[id], parent.category == item.category else { return false }
            return hasValidDependencies(parent, visiting: path)
        }
    }
}
