// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Model/*.swift

import CoreGraphics
import Foundation

final class FakeFiles: @unchecked Sendable {
    var existing: Set<String> = []
    var written: [String] = []
    var removed: [String] = []
    var writeError: CocoaError?

    var files: PasteImageFiles {
        PasteImageFiles(
            write: { _, url in
                let name = url.lastPathComponent
                if self.existing.contains(name) { throw CocoaError(.fileWriteFileExists) }
                if let error = self.writeError {
                    self.existing.insert(name)
                    throw error
                }
                self.existing.insert(name)
                self.written.append(name)
            },
            remove: {
                self.removed.append($0.lastPathComponent)
                self.existing.remove($0.lastPathComponent)
            })
    }
}

func gate(finder: Int32? = 7) -> PasteImageGate {
    var gate = PasteImageGate()
    gate.finderPID = finder
    return gate
}

func down(
    _ gate: inout PasteImageGate, key: Int64 = 9, flags: CGEventFlags = .maskCommand, isRepeat: Bool = false,
    types: [String] = ["public.png"]
) -> PasteImageGate.Verdict {
    gate.keyDown(keyCode: key, flags: flags, isRepeat: isRepeat, clipboardTypes: { types })
}

@main
enum PasteImagePolicyTests {
    static func main() {
        clipboard()
        keys()
        saving()
        print("nc-PasteImage-policy-test: PASS")
    }

    static func clipboard() {
        let images = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif", "org.webmproject.webp"]
        for type in images {
            precondition(PasteImagePolicy.accepts(types: ["public.utf8-plain-text", type]), "\(type) is an image")
        }
        precondition(PasteImagePolicy.imageType(in: ["public.utf8-plain-text"]) == nil, "text keeps Finder's paste")
        precondition(PasteImagePolicy.imageType(in: ["public.tiff", "public.png"]) == "public.png", "PNG wins")
        precondition(PasteImagePolicy.imageType(in: ["public.file-url", "public.png"]) == nil, "a copied file stays a file")
        precondition(PasteImagePolicy.imageType(in: ["public.jpeg"]) == "public.jpeg", "a JPEG is converted")
        precondition(
            PasteImagePolicy.imageType(in: ["public.utf8-plain-text", "public.tiff", "public.jpeg"]) == "public.tiff",
            "else the first image type")
        precondition(!PasteImagePolicy.accepts(types: ["public.file-url", "public.tiff"]), "copied files keep Finder's")
        precondition(!PasteImagePolicy.accepts(types: ["public.utf8-plain-text"]), "text is no image")
        precondition(!PasteImagePolicy.accepts(types: []), "an empty clipboard is no image")
        func passes(_ pid: Int32, _ role: String?) -> Bool {
            PasteImagePolicy.passesThrough(focus: PasteImageFocus(pid: pid, role: role), finderPID: 7)
        }
        precondition(passes(7, "AXTextField"), "rename field takes text")
        precondition(passes(7, "AXTextArea"), "text area takes text")
        precondition(passes(7, "AXComboBox"), "Connect to Server's address field takes text")
        precondition(passes(7, "AXSecureTextField"), "a password field takes text")
        precondition(!passes(7, "AXOutline"), "the file list takes the image")
        precondition(passes(99, "AXOutline"), "a panel over Finder keeps its ⌘V")
        precondition(passes(7, nil), "an unreadable role gets ⌘V back")
        precondition(PasteImagePolicy.passesThrough(focus: nil, finderPID: 7), "an unreadable focus gets ⌘V back")
        func accepts(_ path: String?, window: Bool = true) -> Bool {
            PasteImagePolicy.accepts(frontFolder: path.flatMap(URL.init(string:)), hasWindow: window)
        }
        precondition(accepts("file:///Volumes/Disk/Pictures/"), "a folder window takes the image")
        precondition(accepts(nil, window: false), "no window: the Desktop takes it")
        precondition(!accepts(nil), "a search or Recents has no folder")
        precondition(!accepts("file:///Volumes/Disk/.Trash/"), "the Trash takes nothing")
        precondition(!accepts("file:///Volumes/Stick/.Trashes/501/"), "nor a volume's Trash")
        precondition(!accepts("smb://server/share/"), "only a file URL is a folder")
        precondition(PasteImagePolicy.keyCode(commandCharacter: { _ in nil }) == 9, "fallback is kVK_ANSI_V")
        precondition(PasteImagePolicy.keyCode(commandCharacter: { $0 == 47 ? "v" : "x" }) == 47, "Dvorak's ⌘V")
        let utc = TimeZone(secondsFromGMT: 0)!
        precondition(
            PasteImagePolicy.fileName(at: Date(timeIntervalSince1970: 0), timeZone: utc, attempt: 1)
                == "Pasted_Image_19700101_000000.png", "Vorssaint's name")
        let warsaw = TimeZone(identifier: "Europe/Warsaw")!
        precondition(
            PasteImagePolicy.fileName(at: Date(timeIntervalSince1970: 1_700_000_000.9), timeZone: warsaw, attempt: 3)
                == "Pasted_Image_20231114_231320 3.png", "local time and the third name")
        precondition(PasteImageFailure.finder(status: -1743) == .automationRefused, "Automation refused")
        precondition(PasteImageFailure.finder(status: -1744) == .automationRefused, "consent would be asked")
        for status in [-600, -609, -1712, -1728, 0] {
            precondition(PasteImageFailure.finder(status: status) == .finderSilent, "status \(status) is no answer")
        }
    }

    static func keys() {
        var subject = gate()
        precondition(down(&subject) == .paste(finderPID: 7), "plain ⌘V in Finder with an image pastes")
        precondition(down(&subject, isRepeat: true) == .swallow, "its auto-repeat is swallowed")
        precondition(subject.keyUp(keyCode: 9) == .swallow, "its key-up is swallowed")
        precondition(subject.keyUp(keyCode: 9) == .pass, "one key-up only")

        precondition(down(&subject) == .pass, "a ⌘V while saving is a normal ⌘V")
        precondition(down(&subject, isRepeat: true) == .pass, "and so is its auto-repeat")
        precondition(subject.keyUp(keyCode: 9) == .pass, "and its key-up")
        subject.isSaving = false
        precondition(down(&subject) == .paste(finderPID: 7), "once saved, ⌘V pastes again")
        precondition(subject.keyUp(keyCode: 9) == .swallow)

        for flags: CGEventFlags in [
            [.maskCommand, .maskShift], [.maskCommand, .maskAlternate], [.maskCommand, .maskControl],
            [.maskCommand, .maskSecondaryFn], [],
        ] {
            var fresh = gate()
            precondition(down(&fresh, flags: flags) == .pass, "only plain ⌘V: \(flags.rawValue)")
            precondition(fresh.keyUp(keyCode: 9) == .pass, "a passed key's key-up passes")
        }
        var caps = gate()
        precondition(down(&caps, flags: [.maskCommand, .maskAlphaShift]) == .paste(finderPID: 7), "Caps Lock is no modifier")

        var other = gate()
        var reads = 0
        precondition(
            other.keyDown(keyCode: 8, flags: .maskCommand, isRepeat: false, clipboardTypes: { reads += 1; return [] })
                == .pass, "⌘C passes")
        var notFinder = gate(finder: nil)
        precondition(
            notFinder.keyDown(keyCode: 9, flags: .maskCommand, isRepeat: false, clipboardTypes: { reads += 1; return [] })
                == .pass, "outside Finder ⌘V passes")
        precondition(reads == 0, "only a plain ⌘V in Finder reads the clipboard")

        var files = gate()
        precondition(down(&files, types: ["public.file-url", "public.png"]) == .pass, "copied files: Finder's paste")
        precondition(files.keyUp(keyCode: 9) == .pass)
        var text = gate()
        precondition(down(&text, types: ["public.utf8-plain-text"]) == .pass, "text: Finder's paste")

        var stray = gate()
        precondition(down(&stray, isRepeat: true) == .pass, "a repeat of a key never taken passes")
        precondition(down(&stray) == .paste(finderPID: 7))
        precondition(stray.keyUp(keyCode: 8) == .pass, "another key's key-up passes")
        precondition(stray.keyUp(keyCode: 9) == .swallow)

        var layout = gate()
        layout.keyCode = 47
        precondition(down(&layout) == .pass, "the layout's ⌘V key, not ANSI V")
        precondition(down(&layout, key: 47) == .paste(finderPID: 7))
    }

    static func saving() {
        let date = Date(timeIntervalSince1970: 0)
        let utc = TimeZone(secondsFromGMT: 0)!
        let folder = URL(filePath: "/Volumes/Disk/Pictures", directoryHint: .isDirectory)
        let first = "Pasted_Image_19700101_000000"
        func save(_ fake: FakeFiles) -> PasteImageWrite {
            PasteImageSaver.save(Data([1]), into: folder, at: date, timeZone: utc, files: fake.files)
        }

        var fake = FakeFiles()
        precondition(save(fake) == .saved(folder.appending(path: "\(first).png")), "the first name, in Finder's folder")
        precondition(fake.written == ["\(first).png"] && fake.removed.isEmpty, "one file written, nothing removed")

        fake = FakeFiles()
        fake.existing = ["\(first).png"]
        precondition(save(fake) == .saved(folder.appending(path: "\(first) 2.png")), "a clash: \" 2\"")
        fake.existing = ["\(first).png", "\(first) 2.png"]
        fake.written = []
        precondition(save(fake) == .saved(folder.appending(path: "\(first) 3.png")), "then \" 3\"")
        precondition(fake.removed.isEmpty, "a taken file is never removed")

        fake = FakeFiles()
        fake.existing = Set((1...10).map { PasteImagePolicy.fileName(at: date, timeZone: utc, attempt: $0) })
        let before = fake.existing
        precondition(save(fake) == .failed(code: CocoaError.fileWriteFileExists.rawValue), "ten clashes fail")
        precondition(fake.written.isEmpty && fake.removed.isEmpty && fake.existing == before, "nothing overwritten")

        fake = FakeFiles()
        fake.writeError = CocoaError(.fileWriteNoPermission)
        precondition(save(fake) == .failed(code: CocoaError.fileWriteNoPermission.rawValue), "an unwritable folder")
        precondition(fake.removed == ["\(first).png"] && fake.existing.isEmpty, "a half-written file is removed")

        fake = FakeFiles()
        fake.writeError = CocoaError(.fileWriteOutOfSpace)
        fake.existing = ["\(first).png"]
        precondition(save(fake) == .failed(code: CocoaError.fileWriteOutOfSpace.rawValue), "a full disk")
        precondition(fake.removed == ["\(first) 2.png"] && fake.existing == ["\(first).png"],
                     "only its own half-written file goes, never the taken one")
    }
}
