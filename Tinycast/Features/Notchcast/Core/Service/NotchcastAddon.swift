import SwiftUI

/// One add-on folder's whole declaration; the core wires every part of it.
@MainActor
protocol NotchcastAddon {
    static var switches: [NotchcastSwitch] { get }
    static var commands: [NotchcastCommand] { get }
    static var settings: [NotchcastSettingsRow] { get }
    static var taps: [NotchcastTap] { get }
    /// Built when any of the add-on's switches is enabled, stopped when the last goes off.
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)?
    /// Built and started at core start whatever the switches say, stopped at core stop.
    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)?
}

extension NotchcastAddon {
    static var commands: [NotchcastCommand] { [] }
    static var settings: [NotchcastSettingsRow] { [] }
    static var taps: [NotchcastTap] { [] }
    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? { nil }
    static func makeRecovery(_ context: NotchcastContext) -> (any NotchcastModule)? { nil }
}

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

/// A launcher command; its entry id doubles as the hotkey's key, `hotkey.command:nc-<slug>`.
struct NotchcastCommand: Identifiable, Sendable {
    static let idPrefix = "command:nc-"

    let slug: String
    let name: String
    let symbol: String
    let switchID: String
    var keywords: [String] = []
    let run: @MainActor @Sendable (NotchcastContext) -> Void
    /// An inline launcher field; a hotkey or an empty field still runs `run`.
    var argument: NotchcastArgument?

    var id: String { Self.idPrefix + slug }
}

/// The one free-text field a command takes in the launcher, handed its typed text.
struct NotchcastArgument: Sendable {
    let title: String
    let run: @MainActor @Sendable (NotchcastContext, String) -> Void
}

/// An extra settings row shown under its switch, built with the add-on's own context.
struct NotchcastSettingsRow: Sendable {
    let switchID: String
    var searchTerms: [String] = []
    let view: @MainActor @Sendable (NotchcastContext) -> AnyView
}
