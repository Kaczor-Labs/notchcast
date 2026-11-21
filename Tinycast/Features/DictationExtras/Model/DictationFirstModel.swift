import Foundation

/// The speech model a fresh Notchcast profile starts on; a stored choice always stands.
enum DictationFirstModel {
    static func seed(stored: String?) -> String? {
        stored == nil ? "ultra" : nil
    }
}
