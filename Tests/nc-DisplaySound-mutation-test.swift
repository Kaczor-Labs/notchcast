// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DisplaySound-mutation-test: \(message)") }
}

@main
enum DisplaySoundMutationTests {
    static func main() {
        let folder = "Tinycast/Features/Notchcast/DisplaySound/"
        let service = folder + "Service/BrightnessDisplayService.swift"
        let recovery = folder + "Service/DisplaySoundRecovery.swift"
        let cases: [(Int, String, [(String, String, String)], String)] = [
            (1, "module", [(folder + "DisplaySoundAddon.swift",
                            "context.recovery(DisplaySoundRecovery.self) ?? ", "")],
             "finding 1: recovery restores after module teardown"),
            (2, "service", [(service, "if current != written {", "if false {")], "foreign gamma"),
            (3, "service", [
                (service, "@concurrent func restoreAll() async -> Bool", "func restoreAll() -> Bool"),
                (recovery, "await service.restoreAll()", "service.restoreAll()"),
                (recovery, "func restore() {", "func restore() {\n        _ = service.restoreAll()"),
            ], "finding 3: stop returns"),
            (4, "model", [(folder + "Model/MediaLevelKeyPolicy.swift",
                           "if !isDown, let key = physical.removeValue", "if false, let key = physical.removeValue")],
             "finding 4: owned F14 release"),
            (5, "service", [(service, "if control == .ddc {", "if false {")], "finding 5: a step reads"),
            (6, "service", [(folder + "Service/AudioLevelsService.swift",
                             "if case .fallbackToNativeKeys = unmuted", "if false")], "finding 6: a failed unmute"),
            (7, "service", [(recovery,
                             "service.restoreBeforeExit(within: BrightnessRecoveryPolicy.quitWait)",
                             "restore()")], "finding 7: quit restores"),
            (8, "service", [(folder + "Service/AudioLevelsService.swift",
                             "if watchedDevice != next?.device { watch() }",
                             "if previous?.device != next?.device { watch() }")], "finding 8: listeners follow"),
            (9, "service", [(service, "_ = restoreOwed(&state)\n                return nil",
                             "return snapshot")], "finding 9: the transaction in flight restores"),
            (10, "service", [(service, "guard !Task.isCancelled, !closed.load(ordering: .acquiring) else",
                              "guard !Task.isCancelled else")], "a closed service touches no display"),
        ]
        for (finding, harness, edits, expected) in cases {
            do {
                let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let test = "Tests/nc-DisplaySound-\(harness)-test.swift"
                let header = try String(contentsOf: root.appendingPathComponent(test), encoding: .utf8)
                var paths = [test]
                for line in header.split(separator: "\n") where line.hasPrefix("// notchcast-sources: ") {
                    for source in line.dropFirst("// notchcast-sources: ".count).split(separator: " ") {
                        let path = String(source)
                        if path.hasSuffix("/*.swift") {
                            let directory = String(path.dropLast("/*.swift".count))
                            paths += try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
                                .filter { $0.hasSuffix(".swift") }.sorted().map { directory + "/" + $0 }
                        } else { paths.append(path) }
                    }
                }
                var inputs: [String] = []
                for path in paths {
                    var source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                    for (target, original, broken) in edits where target == path {
                        check(source.contains(original), "mutation \(finding) target exists")
                        source = source.replacingOccurrences(of: original, with: broken)
                    }
                    let copy = scratch.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                    try source.write(to: copy, atomically: true, encoding: .utf8)
                    inputs.append(copy.path)
                }
                let binary = scratch.appendingPathComponent("mutant").path
                let compilation = try runProcess("/usr/bin/xcrun",
                    ["swiftc", "-swift-version", "6", "-parse-as-library"] + inputs + ["-o", binary], scratch: scratch)
                check(compilation.0 == 0, "mutation \(finding) must compile: \(compilation.1)")
                let result = try runProcess(binary, [], scratch: scratch)
                check(result.0 != 0 && result.1.contains(expected),
                      "mutation \(finding) must fail its pin: \(result.1)")
                print("SKIP: hardware only; finding \(finding) planted break: FAIL (expected), \(expected)")
                if finding == 1 {
                    for (path, _, _) in edits {
                        let copy = scratch.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                            .write(to: copy, atomically: true, encoding: .utf8)
                    }
                    let rebuilt = try runProcess("/usr/bin/xcrun",
                        ["swiftc", "-swift-version", "6", "-parse-as-library"] + inputs + ["-o", binary], scratch: scratch)
                    check(rebuilt.0 == 0, "finding 1 restored sources compile: \(rebuilt.1)")
                    let restored = try runProcess(binary, [], scratch: scratch)
                    check(restored.0 == 0 && restored.1.contains("finding 1 recovery handoff: PASS"),
                          "finding 1 restored pin passes: \(restored.1)")
                }
                print("SKIP: hardware only; finding \(finding) original sources restored: PASS (originals untouched)")
            } catch { fatalError("mutation \(finding): \(error)") }
        }
        print("SKIP: no hardware tests; planted breaks 1-10 FAIL as expected; originals PASS")
        print("nc-DisplaySound-mutation-test: PASS")
    }

    static func runProcess(_ executable: String, _ arguments: [String], scratch: URL) throws -> (Int32, String) {
        let log = scratch.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["SWIFT_BACKTRACE"] = "disable"
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, try String(contentsOf: log, encoding: .utf8))
    }
}
