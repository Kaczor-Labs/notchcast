import Foundation

extension TaildropEnvironment {
    static let live = TaildropEnvironment(
        finderSelection: { try await TaildropFinder.selection() },
        findCLI: {
            // An app started from Finder gets a bare PATH, so Homebrew and the Mac app are tried too.
            let folders = ["/opt/homebrew/bin", "/usr/local/bin"]
                + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            let candidates = folders.map { $0 + "/tailscale" } + ["/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
            return candidates.first { path in
                var isFolder = ObjCBool(false)
                return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
                    && FileManager.default.isExecutableFile(atPath: path)
            }.map { URL(filePath: $0) }
        },
        zipTool: URL(filePath: "/usr/bin/ditto"),
        inspect: { item in
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                let isFolder = values.isDirectory
            else { return nil }
            return isFolder ? .folder : .file(bytes: Int64(values.fileSize ?? 0))
        },
        makeScratch: {
            let folder = FileManager.default.temporaryDirectory.appending(path: "notchcast-taildrop-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            return folder
        },
        remove: { try? FileManager.default.removeItem(at: $0) },
        run: { try await TaildropProcess.run($0, onBytes: $1) }
    )
}

/// Asks Finder for its selection with `core/getd` Apple Events, 5 s each.
private enum TaildropFinder {
    static let replySeconds: TimeInterval = 5
    static let notPermitted = -1743
    static let timedOut = -1712

    @concurrent
    static func selection() async throws -> [URL] {
        try ask(property("sele", of: .null())).flatMap { try ask(property("pURL", of: $0)) }
            .compactMap { $0.stringValue.flatMap(URL.init(string:)) }.filter(\.isFileURL)
    }

    private static func property(_ name: String, of owner: NSAppleEventDescriptor) -> NSAppleEventDescriptor? {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(owner, forKeyword: fourCharacters("from"))
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharacters("prop")), forKeyword: fourCharacters("want"))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharacters("prop")), forKeyword: fourCharacters("form"))
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharacters(name)), forKeyword: fourCharacters("seld"))
        return specifier.coerce(toDescriptorType: fourCharacters("obj "))
    }

    /// A refused grant and a timeout are failures; anything else reads as nothing selected.
    private static func ask(_ object: NSAppleEventDescriptor?) throws -> [NSAppleEventDescriptor] {
        guard let object else { return [] }
        try Task.checkCancellation()
        let request = NSAppleEventDescriptor(
            eventClass: fourCharacters("core"), eventID: fourCharacters("getd"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
            returnID: -1, transactionID: 0)
        request.setParam(object, forKeyword: fourCharacters("----"))
        let reply: NSAppleEventDescriptor?
        let status: Int
        do {
            let answered = try request.sendEvent(options: [.waitForReply, .canInteract], timeout: replySeconds)
            reply = answered
            status = Int(answered.paramDescriptor(forKeyword: fourCharacters("errn"))?.int32Value ?? 0)
        } catch {
            reply = nil
            status = (error as NSError).code
        }
        if status == notPermitted { throw TaildropFailure.finderNeedsAutomation }
        if status == timedOut { throw TaildropFailure.finderTimedOut }
        guard let answer = reply?.paramDescriptor(forKeyword: fourCharacters("----")) else { return [] }
        guard answer.descriptorType == fourCharacters("list") else { return [answer] }
        return (0..<answer.numberOfItems).compactMap { answer.atIndex($0 + 1) }
    }

    private static func fourCharacters(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
