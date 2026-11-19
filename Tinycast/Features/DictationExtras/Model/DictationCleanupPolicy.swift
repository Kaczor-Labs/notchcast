import Foundation

/// Whether a finished dictation sends its transcript to the cleanup model.
enum DictationCleanupPolicy {
    static func sends(switchOn: Bool, cleansUp: Bool, hasField: Bool, liveTextEmpty: Bool) -> Bool {
        switchOn && cleansUp && !hasField && liveTextEmpty
    }
}
