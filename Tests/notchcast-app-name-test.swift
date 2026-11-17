// notchcast-sources: Tinycast/Platform/AppDisplayName.swift
// notchcast-reads: notchcast/name-override.py Tinycast/**/*.xcstrings
import Foundation

/// A Debug build and a test copy with its own bundle id never show the plain release name: the name
/// override phase names them from PRODUCT_NAME and the bundle id, and `appDisplayName` reads it back.
@main
struct NotchcastAppNameTest {
    static let dialog = "An app or web page asked Tinycast to run this. Allow only links you trust."
    static let keepAwake = "Notchcast will try again."

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchcast-app-name-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cases = [
            ("Notchcast", "app.notchcast", "Notchcast"),
            ("Notchcast Dev", "app.notchcast.dev", "Notchcast Dev"),
            ("Notchcast Dev", "app.notchcast.dev.g818", "Notchcast Dev g818"),
        ]
        for (product, bundleID, expected) in cases {
            let app = root.appending(path: bundleID).appending(path: "\(product).app")
            try write(app.appending(path: "Contents/Info.plist"), [
                "CFBundleName": product, "CFBundleExecutable": product, "CFBundleIdentifier": bundleID,
            ])
            let english = app.appending(path: "Contents/Resources/en.lproj")
            try write(english.appending(path: "Localizable.strings"), ["Quit Tinycast": "Quit Tinycast"])
            try write(english.appending(path: "InfoPlist.strings"), [:])
            try write(english.appending(path: "Notchcast.strings"), ["Notchcast": "Notchcast"])
            for _ in 0..<2 {
                try run(["notchcast/name-override.py"], env: [
                    "TARGET_BUILD_DIR": app.deletingLastPathComponent().path, "WRAPPER_NAME": app.lastPathComponent,
                    "DERIVED_FILE_DIR": app.deletingLastPathComponent().path,
                    "PRODUCT_NAME": product, "PRODUCT_BUNDLE_IDENTIFIER": bundleID,
                ])
            }
            let printed = try run(["notchcast/name-override.py", "--name", product, bundleID])
            precondition(printed == expected, "\(bundleID): --name printed \(printed), not \(expected)")
            let bundle = try require(Bundle(url: app), "\(bundleID): no bundle")
            precondition(bundle.appDisplayName == expected, "\(bundleID): reads \(bundle.appDisplayName)")
            precondition(bundle.infoDictionary?["CFBundleExecutable"] as? String == product,
                         "\(bundleID): the executable name must not follow the display name")
            let table = try read(english.appending(path: "Localizable.strings"))
            let asked = dialog.replacingOccurrences(of: "Tinycast", with: expected)
            precondition(table[dialog] == asked, "\(bundleID): the link dialog says \(table[dialog] ?? "nothing")")
            precondition(table["Quit Tinycast"] == "Quit \(expected)", "\(bundleID): \(table["Quit Tinycast"] ?? "")")
            let awake = (try? read(english.appending(path: "NotchcastKeepAwake.strings"))) ?? [:]
            let renamed = expected == "Notchcast" ? nil : keepAwake.replacingOccurrences(of: "Notchcast", with: expected)
            precondition(awake[keepAwake] == renamed, "\(bundleID): Keep Awake says \(awake[keepAwake] ?? "its key")")
            let fork = try read(english.appending(path: "Notchcast.strings"))
            precondition(fork["Notchcast"] == "Notchcast", "\(bundleID): the module category was renamed")
            try run(["notchcast/name-override.py", "--verify", app.path])
            print("PASS  \(bundleID) shows \(expected)")
        }
        print("notchcast-app-name-test: PASS")
    }

    static func write(_ url: URL, _ plist: [String: String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
    }

    static func read(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String], "\(url.path)")
    }

    static func require<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else { fatalError("missing: \(what)") }
        return value
    }

    @discardableResult
    static func run(_ arguments: [String], env: [String: String] = [:]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "python3 \(arguments.joined(separator: " ")) failed")
        return try require(String(bytes: data, encoding: .utf8), "python3 output")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
