import Darwin
import Foundation
import Security

nonisolated enum NotchcastCodeCheck { // drift: keep Taildrop calls this in the next PR for #1255.
    static func file(_ url: URL, satisfies requirement: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              let required = parse(requirement)
        else { return false }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSSingleThreaded)
        return SecStaticCodeCheckValidityWithErrors(code, flags, required, nil) == errSecSuccess
    }

    static func process(_ pid: pid_t, satisfies requirement: String) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              let required = parse(requirement)
        else { return false }

        return SecCodeCheckValidityWithErrors(code, [], required, nil) == errSecSuccess
    }

    private static func parse(_ requirement: String) -> SecRequirement? {
        var required: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &required) == errSecSuccess
        else { return nil }
        return required
    }
}
