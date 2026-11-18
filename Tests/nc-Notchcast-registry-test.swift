// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastPane.swift
// notchcast-reads: Tinycast/Features/Notchcast/**
import Foundation

// Reads the add-on folders as text: compiling them would pull their UI into a model harness.
struct AddonSource {
    struct Switch {
        let id: String
        let category: String
        let dependencies: [String]
        let path: String
    }

    var switches: [Switch] = []
    var slugs: [(slug: String, path: String)] = []
    var userPaths: Set<String> = []
    var addonTypes: [String: String] = [:]
    var folderOf: [String: String] = [:]

    init(files: [String: String]) {
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let folder = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            for call in Self.calls("NotchcastSwitch(", in: text) {
                switches.append(
                    Switch(
                        id: Self.first(#"id:\s*"([^"]+)""#, in: call) ?? "",
                        category: Self.first(#"category:\s*\.(\w+)"#, in: call) ?? "",
                        dependencies: Self.first(#"dependencies:\s*\[([^\]]*)\]"#, in: call)
                            .map { Self.all(#""([^"]+)""#, in: $0) } ?? [],
                        path: path))
            }
            slugs += Self.all(#"\bslug:\s*"([^"]+)""#, in: text).map { ($0, path) }
            userPaths.formUnion(Self.all(#"\bswitchID:\s*"([^"]+)""#, in: text))
            if text.contains("func makeModule(") {
                for call in Self.calls("NotchcastSwitch(", in: text) {
                    if let id = Self.first(#"id:\s*"([^"]+)""#, in: call) { userPaths.insert(id) }
                }
            }
            for type in Self.all(#"\b(?:struct|enum|class)\s+(\w+)\b[^{]*\bNotchcastAddon\b"#, in: text) {
                addonTypes[type] = path
                folderOf[type] = folder
            }
        }
    }

    static func calls(_ name: String, in text: String) -> [String] {
        var result: [String] = []
        var rest = text[...]
        while let start = rest.range(of: name) {
            var depth = 0
            var inString = false
            var previous: Character = " "
            var end = rest.endIndex
            for index in rest[start.upperBound...].indices {
                let character = rest[index]
                if character == "\"" && previous != "\\" { inString.toggle() }
                if !inString {
                    if character == "(" { depth += 1 }
                    if character == ")" {
                        if depth == 0 {
                            end = index
                            break
                        }
                        depth -= 1
                    }
                }
                previous = character
            }
            result.append(String(rest[start.upperBound..<end]))
            rest = end < rest.endIndex ? rest[rest.index(after: end)...] : rest[rest.endIndex...]
        }
        return result
    }

    static func all(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { fatalError("bad pattern \(pattern)") }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func first(_ pattern: String, in text: String) -> String? { all(pattern, in: text).first }
}

enum RegistryCheck {
    // Shipped v1 raw values: reused verbatim so stored prefs and bound hotkeys survive.
    static let frozenIDs: Set<String> = [
        "screenshot", "displayBrightness", "volumeLevels", "hideCommandM", "middleClick", "quitProtection",
        "showDesktop", "launcherNumberKeys", "smallCommands", "downloads", "downloadsAria2", "distill",
        "distillTimestamps", "musicBlockAppleMusic", "iPhoneBackupTweaks",
    ]
    // Switch ids v1 never shipped; an id in neither list is a typo or a rename of a shipped one.
    static let newIDs: Set<String> = ["spotify", "dayPage"]
    static let frozenSlugs: Set<String> = ["screenshot-area", "screenshot-display"]

    /// Problems fail the harness; notes only report (an absent dependency counts as off).
    static func run(files: [String: String], registry: String, newIDs: Set<String> = newIDs)
        -> (problems: [String], notes: [String]) {
        let source = AddonSource(files: files)
        var problems: [String] = []
        var notes: [String] = []
        let categories = Set(NotchcastCategory.allCases.map(\.rawValue))
        let ids = source.switches.map(\.id)
        let declared = Set(ids)
        for (id, owners) in Dictionary(grouping: source.switches, by: \.id).mapValues({ $0.map(\.path) })
        where owners.count > 1 {
            problems.append("switch id \(id) declared twice: \(owners.joined(separator: ", "))")
        }
        for id in frozenIDs.intersection(newIDs) { problems.append("switch id \(id) is both shipped and new") }
        let slugs = source.slugs.map(\.slug)
        for slug in Set(slugs) where slugs.filter({ $0 == slug }).count > 1 {
            problems.append("command slug \(slug) declared twice")
        }
        for item in source.switches {
            if item.id.isEmpty { problems.append("\(item.path): a switch without a literal id") }
            if !item.id.isEmpty && !frozenIDs.contains(item.id) && !newIDs.contains(item.id) {
                problems.append("\(item.path): switch id \(item.id) is neither a shipped v1 id nor listed in newIDs")
            }
            if !categories.contains(item.category) {
                problems.append("\(item.path): switch \(item.id) has no valid category (\(item.category))")
            }
            if !source.userPaths.contains(item.id) {
                problems.append("\(item.path): switch \(item.id) has no user path (command, settings row, tap or module)")
            }
            for dependency in item.dependencies where !declared.contains(dependency) {
                notes.append("switch \(item.id) depends on \(dependency), which no add-on declares; it counts as off")
            }
        }
        for (slug, path) in source.slugs {
            if slug.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) == nil {
                problems.append("\(path): command slug \(slug) is not lowercase-kebab")
            }
            if let frozen = frozenSlugs.first(where: { $0.replacingOccurrences(of: "-", with: "")
                == slug.replacingOccurrences(of: "-", with: "") && $0 != slug }) {
                problems.append("\(path): command slug \(slug) renames the shipped slug \(frozen)")
            }
        }
        let lines = AddonSource.all(#"(?m)^\s*(\w+)\.self,\s*$"#, in: registry)
        for type in lines where source.addonTypes[type] == nil {
            problems.append("registry names \(type), which no add-on folder declares `: NotchcastAddon`")
        }
        for (type, path) in source.addonTypes where !lines.contains(type) {
            problems.append("\(path): \(type) has no registry line")
        }
        for (folder, types) in Dictionary(grouping: source.folderOf, by: \.value) where types.count > 1 {
            problems.append("folder \(folder) declares \(types.count) add-ons; one per folder")
        }
        return (problems.sorted(), notes.sorted())
    }
}

@main
enum NotchcastRegistryTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func repoFiles() throws -> (files: [String: String], registry: String) {
        let root = URL(filePath: "Tinycast/Features/Notchcast")
        let registry = try String(contentsOf: root.appending(path: "NotchcastRegistry.swift"), encoding: .utf8)
        var files: [String: String] = [:]
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !["Core", "Hidden"].contains($0.lastPathComponent) }
        for folder in folders {
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                files["\(folder.lastPathComponent)/\(url.lastPathComponent)"] = try String(contentsOf: url, encoding: .utf8)
            }
        }
        return (files, registry)
    }

    static func main() throws {
        let shots = """
            enum ShotsAddon: NotchcastAddon {
                static let switches = [
                    NotchcastSwitch(id: "screenshot", title: String(localized: "Shots (beta)", table: "T"),
                                    subtitle: "", category: .music, dependencies: ["absentSwitch"])
                ]
                static let commands = [
                    NotchcastCommand(slug: "screenshot-area", name: "", symbol: "", switchID: "screenshot") { _ in }
                ]
            }
            """
        let clean = RegistryCheck.run(files: ["Shots/ShotsAddon.swift": shots], registry: "    ShotsAddon.self,\n")
        expect(clean.problems.isEmpty, "a well-formed add-on passes: \(clean.problems)")
        expect(clean.notes == ["switch screenshot depends on absentSwitch, which no add-on declares; it counts as off"],
               "an absent dependency is reported, not failed: \(clean.notes)")

        let planted: [(String, String, String)] = [
            (shots.replacingOccurrences(of: "id: \"screenshot\"", with: "id: \"screenShot\""), "",
             "switch id screenShot is neither a shipped v1 id"),
            (shots.replacingOccurrences(of: "\"screenshot\"", with: "\"launcherNumberKey\""), "",
             "switch id launcherNumberKey is neither a shipped v1 id"),
            (shots.replacingOccurrences(of: ".music", with: ".nowhere"), "", "has no valid category"),
            (shots.replacingOccurrences(of: "switchID: \"screenshot\"", with: "switchID: \"other\""), "", "has no user path"),
            (shots.replacingOccurrences(of: "slug: \"screenshot-area\"", with: "slug: \"screenshotArea\""), "",
             "not lowercase-kebab"),
            (shots, "    OtherAddon.self,\n", "registry names OtherAddon"),
            (shots + "\nstruct SecondAddon: NotchcastAddon {}\n", "    ShotsAddon.self,\n    SecondAddon.self,\n",
             "declares 2 add-ons"),
            (shots + shots.replacingOccurrences(of: "ShotsAddon", with: "TwinAddon"), "", "switch id screenshot declared twice"),
        ]
        for (text, registry, needle) in planted {
            let result = RegistryCheck.run(files: ["Shots/ShotsAddon.swift": text],
                                           registry: registry.isEmpty ? "    ShotsAddon.self,\n    TwinAddon.self,\n" : registry)
            expect(result.problems.contains { $0.contains(needle) }, "planted breach caught (\(needle)): \(result.problems)")
        }
        let twinText = shots.replacingOccurrences(of: "Shots", with: "Twin")
        let twin = RegistryCheck.run(
            files: ["Shots/ShotsAddon.swift": shots, "Twin/TwinAddon.swift": twinText],
            registry: "    ShotsAddon.self,\n    TwinAddon.self,\n")
        expect(twin.problems.contains("switch id screenshot declared twice: Shots/ShotsAddon.swift, Twin/TwinAddon.swift"),
               "a pinned id in two folders is caught: \(twin.problems)")
        let fresh = shots.replacingOccurrences(of: "\"screenshot\"", with: "\"screenRuler\"")
        expect(RegistryCheck.run(files: ["Shots/ShotsAddon.swift": fresh], registry: "    ShotsAddon.self,\n",
                                 newIDs: ["screenRuler"]).problems.isEmpty, "an id named in newIDs passes")

        let (files, registry) = try repoFiles()
        let real = RegistryCheck.run(files: files, registry: registry)
        for note in real.notes { print("note: \(note)") }
        expect(real.problems.isEmpty, "the shipped registry is consistent:\n" + real.problems.joined(separator: "\n"))
        let switches = AddonSource(files: files).switches
        let shown = NotchcastPane.shown(registered: Set(switches.compactMap { NotchcastCategory(rawValue: $0.category) }))
        for item in switches {
            let tabs = shown.filter { $0.categories.map(\.rawValue).contains(item.category) }
            expect(tabs.count == 1, "switch \(item.id) lands in exactly one shown tab: \(tabs)")
        }
        let ids = switches.map(\.id)
        print("registry: \(ids.count) switches in \(Set(files.keys.map { $0.split(separator: "/")[0] }).count) folders")
        print("PASSED")
    }
}
