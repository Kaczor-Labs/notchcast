import Foundation

extension IPhoneBackupSystem {
    struct UnsupportedValue: Error {}

    /// Reads where it writes, so a value inherited from another source is never captured as the user's.
    static func preferences(domain: String, journalFolder: URL) -> IPhoneBackupSystem {
        IPhoneBackupSystem(
            read: {
                let key = IPhoneBackupPolicy.key as CFString
                switch CFPreferencesCopyValue(key, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
                case nil: return nil
                case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                    return .bool(number.boolValue)
                case let number as NSNumber:
                    return CFNumberIsFloatType(number) ? .real(number.doubleValue) : .integer(number.intValue)
                case let string as String: return .string(string)
                default: throw UnsupportedValue()
                }
            },
            write: { write in
                let value: CFPropertyList? = switch write {
                case .set(.bool(let value)): value as NSNumber
                case .set(.integer(let value)): value as NSNumber
                case .set(.real(let value)): value as NSNumber
                case .set(.string(let value)): value as NSString
                case .delete: nil
                }
                let key = IPhoneBackupPolicy.key as CFString
                CFPreferencesSetValue(key, value, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                return CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            },
            journalFolder: journalFolder
        )
    }
}
