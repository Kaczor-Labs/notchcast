// Adapted from tw93 and Mole contributors, lib/clean/user.sh @ f3804188 (GPL-3.0).
import Foundation

enum CleanerBrowserVersions {
    static func areas(home: URL) -> [CleanerArea] {
        ["Google Chrome", "Microsoft Edge", "Brave Browser"].flatMap { name in
            [URL(filePath: "/Applications", directoryHint: .isDirectory), home.appending(path: "Applications")].map {
                let root = $0.appending(path: "\(name).app/Contents/Frameworks/\(name) Framework.framework/Versions")
                return CleanerArea(home: home, kind: .browserVersions, root: root, owner: name)
            }
        }
    }

    static func version(_ name: String) -> [Int]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    static func canMove(
        _ url: URL, file: CleanerFile, in area: CleanerArea, fileSystem: any CleanerFileSystem
    ) throws -> Bool {
        let link = area.root.appending(component: "Current")
        guard file.facts.isDirectory, let version = version(url.lastPathComponent),
            try fileSystem.inspect(link).facts.isSymbolicLink
        else { return false }
        let destination = try fileSystem.linkDestination(of: link)
        guard let currentVersion = Self.version(destination), version.lexicographicallyPrecedes(currentVersion)
        else { return false }
        let current = try fileSystem.inspect(area.root.appending(component: destination))
        return current.facts.isDirectory && !current.facts.isSymbolicLink
            && current.identity.device == file.identity.device && file.modified <= current.modified
    }
}
