import Foundation

extension MacTweaksAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switches[0].id }

    enum Request: Codable, Equatable, Sendable {
        case snapshot
        case set(MacTweak.ID, Bool)
        case undoEverything
    }

    struct Reply: Codable, Sendable {
        var snapshot: MacTweakSnapshot?
        var notice: String?
    }

    static func answer(_ request: Request, context: NotchcastContext) async throws -> Reply {
        guard context.isEnabled(settingsID), let module = context.recovery(MacTweaksModule.self) else {
            throw CancellationError()
        }
        let store = module.store
        do {
            let issues: [MacTweaksStore.Issue]
            switch request {
            case .snapshot: issues = []
            case .set(let id, let on): issues = try await store.set(id, on: on)
            case .undoEverything: issues = try await store.undoEverything()
            }
            let snapshot = try await store.snapshot()
            let notice: String?
            if issues.contains(where: { if case .restart = $0 { true } else { false } }) {
                notice = String(localized: "Finder couldn’t restart. Reopen it to see your changes.",
                                table: "NotchcastMacTweaks")
            } else if !issues.isEmpty {
                notice = String(localized: "Some settings couldn’t be changed. Check their current state and try again.",
                                table: "NotchcastMacTweaks")
            } else {
                notice = nil
            }
            return Reply(snapshot: snapshot, notice: notice)
        } catch MacTweaksStore.Failure.corruptJournal {
            return Reply(notice: String(
                localized: "The undo history can’t be read. Changes are paused to keep it safe.",
                table: "NotchcastMacTweaks"))
        } catch MacTweaksStore.Failure.busy {
            return Reply(notice: String(
                localized: "A change is already in progress. Try again when it finishes.",
                table: "NotchcastMacTweaks"))
        }
    }
}
