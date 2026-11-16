// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When Keep Awake starts and ends on its own. Derived from Vorssaint's KeepAwakeAutomationSupport.
enum KeepAwakeAutomation {
    enum Condition: String, CaseIterable, Sendable { case externalDisplay, power, runningApps }

    enum Action: Sendable, Equatable { case none, activate, deactivate }

    struct Conditions: Sendable, Equatable {
        var externalDisplay = false
        var power = false
        var runningApps = false
        var bundleIDs: [String] = []
        var requiresAll = false

        var isAnyEnabled: Bool { !enabled.isEmpty }

        /// An app condition with no apps chosen cannot hold, so it never counts toward "all".
        var enabled: Set<Condition> {
            var set = Set<Condition>()
            if externalDisplay { set.insert(.externalDisplay) }
            if power { set.insert(.power) }
            if runningApps, !bundleIDs.isEmpty { set.insert(.runningApps) }
            return set
        }

        func matching(_ facts: Facts) -> Set<Condition> {
            var set = Set<Condition>()
            if externalDisplay, facts.externalDisplay { set.insert(.externalDisplay) }
            if power, facts.onPower { set.insert(.power) }
            if runningApps, KeepAwakeAutomation.selectedAppsAreRunning(bundleIDs, facts.runningBundleIDs) {
                set.insert(.runningApps)
            }
            return set
        }

        func areSatisfied(by facts: Facts) -> Bool {
            let matching = matching(facts)
            guard !matching.isEmpty else { return false }
            return requiresAll ? matching == enabled : true
        }
    }

    struct Facts: Sendable, Equatable {
        var externalDisplay = false
        var onPower = false
        var runningBundleIDs: [String] = []
    }

    static func hasExternalDisplay(builtInFlags: [Bool]) -> Bool { builtInFlags.contains(false) }

    static func selectedAppsAreRunning(_ selected: [String], _ running: [String]) -> Bool {
        guard !selected.isEmpty else { return false }
        let selected = Set(selected)
        return running.contains(where: selected.contains)
    }

    static func action(
        conditions: Conditions, facts: Facts, sessionActive: Bool, automaticSessionActive: Bool
    ) -> Action {
        guard conditions.areSatisfied(by: facts) else { return automaticSessionActive ? .deactivate : .none }
        return sessionActive ? .none : .activate
    }
}
