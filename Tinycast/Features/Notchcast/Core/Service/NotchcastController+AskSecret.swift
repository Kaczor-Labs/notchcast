import Foundation

extension NotchcastController {
    /// The asking add-on is named from its registration, so its own strings can never name it.
    func wireAskSecret(
        _ ask: @escaping @MainActor @Sendable (
            _ requester: String, _ title: String, _ message: String?, _ fieldTitle: String, _ confirmTitle: String
        ) async -> String?
    ) {
        for slot in slots {
            let requester = slot.addon.switches.first?.title ?? String(describing: slot.addon)
            for context in [slot.context, slot.recovery] {
                context.askSecret = { title, message, fieldTitle, confirmTitle in
                    await ask(requester, title, message, fieldTitle, confirmTitle)
                }
            }
        }
    }
}
