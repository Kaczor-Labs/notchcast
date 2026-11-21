import Foundation

/// How a protected archive's password reaches HatchZip: asked per job, never stored or on a command line.
nonisolated enum ArchivePassword {
    static let variable = "HATCHZIP_PASSWORD"
    /// HatchZip's own count when it asks on a terminal.
    static let attempts = 3

    enum Step: Equatable, Sendable {
        case ask(wrong: Bool)
        case giveUp
    }

    static func next(asked: Int) -> Step { asked < attempts ? .ask(wrong: asked > 0) : .giveUp }

    /// One run's extra environment: the variable only for HatchZip, and only while a password is held.
    static func environment(_ password: String?, engine: ArchiveEngine) -> [String: String] {
        guard engine == .hatchzip, let password else { return [:] }
        return [variable: password]
    }

    /// A protected 7z or RAR may hide its names, and HatchZip cannot undo a stop of one without the password.
    static func allowsInPlace(fileName: String) -> Bool { fileName.lowercased().hasSuffix(".zip") }
}
