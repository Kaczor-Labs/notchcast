// notchcast-sources: -package-name IslandEngine notchcast/vendor/IslandEngine/Sources/IslandCore/*.swift
// notchcast-reads: notchcast/vendor/IslandEngine/REVISION notchcast/vendor/IslandEngine/Sources/**
import CryptoKit
import Foundation

@main
enum IslandEngineTests {
    static func close(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) <= 1e-9 * max(1, abs(expected)), "\(actual) != \(expected)")
    }

    static func object(_ type: String, _ body: Data) -> Data {
        Data(Insecure.SHA1.hash(data: Data("\(type) \(body.count)\0".utf8) + body))
    }

    // Git's tree id from the files themselves, so archive copies without .git check too.
    static func treeID(_ directory: URL) throws -> Data {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey])
            .map { url -> (key: String, url: URL, isDirectory: Bool) in
                let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                return (url.lastPathComponent + (isDirectory ? "/" : ""), url, isDirectory)
            }
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        var body = Data()
        for entry in entries {
            let executable = try entry.url.resourceValues(forKeys: [.isExecutableKey]).isExecutable == true
            let mode = entry.isDirectory ? "40000" : executable ? "100755" : "100644"
            let id = entry.isDirectory ? try treeID(entry.url) : object("blob", try Data(contentsOf: entry.url))
            body += Data("\(mode) \(entry.url.lastPathComponent)\0".utf8) + id
        }
        return object("tree", body)
    }

    static func checkStamps() throws {
        let vendor = URL(filePath: "notchcast/vendor/IslandEngine")
        let lines = try String(contentsOf: vendor.appending(path: "REVISION"), encoding: .utf8)
            .split(separator: "\n").dropFirst()
        precondition(!lines.isEmpty, "REVISION stamps no module trees")
        for line in lines {
            let fields = line.split(separator: " ").map(String.init)
            let actual = try treeID(vendor.appending(path: "Sources/\(fields[0])"))
                .map { String(format: "%02x", $0) }.joined()
            precondition(actual == fields[1], "\(fields[0]) tree \(actual) != stamped \(fields[1]); rerun the sync")
        }
    }

    static func main() throws {
        try checkStamps()
        let spring = solveSpring(
            SpringConfig(response: 0.46, dampingFraction: 1.5, blendDuration: 0.05),
            x0: -57.296939846128225, v0: 1921.1778063327074, t: 1.8419387640897185)
        close(spring.x, -0.0002804989659694778)
        close(spring.v, 0.0014634504441383817)
        let idle = ShapeTarget(.idle, measure: .empty, screenWidth: 360, metrics: .standard)
        close(idle.left, -47.425)
        close(idle.right, 47.425)
        close(idle.top, 13.91)
        close(idle.height, 36.84)
        close(idle.radius, 18.42)
        let compact = ShapeTarget(.compact, measure: ContentMeasure(
            leading: 85.05258858669549, trailing: 192.03859576955438),
            screenWidth: 360, metrics: .standard)
        close(compact.left, -126.425)
        close(compact.right, 126.675)
        close(compact.height, 36.85)
        print("PASS: Island engine, module trees match REVISION, 10 spring and outline values")
    }
}
