import Foundation

struct NotchcastSettingsStatus: Codable, Equatable, Sendable {
    var addons: [String: Data] = [:]
    var dictationCleanupModel: AIModelSelection?
    var dictationAutomaticModelTitle: String?
    var hasDictationHistory = false
}

enum NotchcastSettingsAction: Codable, Sendable {
    case addon(NotchcastSettingsMessage)
    case selectDictationCleanupModel(AIModelSelection?)
    case restoreAutomaticBackup(URL)
}

struct NotchcastSettingsMessage: Codable, Sendable {
    let id: String
    let payload: Data

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
