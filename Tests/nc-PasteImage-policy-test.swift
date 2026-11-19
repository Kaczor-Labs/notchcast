// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Model/*.swift

import CoreGraphics
import Foundation

final class FakeFiles: @unchecked Sendable {
    var written: [String] = []
    var removed: [String] = []
    var folderFails = false
    var writeFails = false
    let folder = URL(filePath: "/private-tmp/paste", directoryHint: .isDirectory)

    var files: PasteImageFiles {
        PasteImageFiles(
            makeFolder: {
                if self.folderFails { throw CocoaError(.fileWriteNoPermission) }
                return self.folder
            },
            write: { _, url in
                if self.writeFails { throw CocoaError(.fileWriteNoPermission) }
                self.written.append(url.lastPathComponent)
            },
            remove: { self.removed.append($0.lastPathComponent) })
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
        for type in ["public.png", "public.tiff", "public.jpeg", "public.heic"] {
            precondition(PasteImagePolicy.accepts(types: ["public.utf8-plain-text", type]), "\(type) is an image")
        }
        precondition(!PasteImagePolicy.accepts(types: ["public.file-url", "public.tiff"]), "copied files keep Finder's")
        precondition(!PasteImagePolicy.accepts(types: ["public.utf8-plain-text"]), "text is no image")
        precondition(!PasteImagePolicy.accepts(types: []), "an empty clipboard is no image")
        func passes(_ pid: Int32, _ role: String?) -> Bool {
            PasteImagePolicy.passesThrough(focus: PasteImageFocus(pid: pid, role: role), finderPID: 7)
        }
        precondition(passes(7, "AXTextField"), "rename field takes text")
        precondition(passes(7, "AXTextArea"), "text area takes text")
        precondition(passes(7, "AXComboBox"), "Connect to Server's address field takes text")
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
        precondition(
            PasteImagePolicy.fileName(at: Date(timeIntervalSince1970: 1_700_000_000.9), attempt: 3)
                == "Pasted Image 1700000000 3.png", "file name")
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
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var fake = FakeFiles()
        var answers: [PasteImagePlacement] = [.placed]
        var placed: [String] = []
        func place(_ url: URL) -> PasteImagePlacement {
            placed.append(url.lastPathComponent)
            return answers.isEmpty ? .nameTaken : answers.removeFirst()
        }
        precondition(PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "placed")
        precondition(placed == ["Pasted Image 1700000000 1.png"], "first name: \(placed)")
        precondition(fake.removed == ["paste"], "the folder is removed after success")

        fake = FakeFiles()
        placed = []
        answers = [.nameTaken, .nameTaken, .placed]
        precondition(PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "a clash retries")
        precondition(placed.map { $0.split(separator: " ").last! } == ["1.png", "2.png", "3.png"], "next number")
        precondition(fake.removed == ["Pasted Image 1700000000 1.png", "Pasted Image 1700000000 2.png", "paste"],
                     "each clashed file and the folder go: \(fake.removed)")

        fake = FakeFiles()
        placed = []
        answers = []
        precondition(!PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "ten clashes fail")
        precondition(placed.count == 10 && placed.last == "Pasted Image 1700000000 10.png", "up to 10 times")
        precondition(fake.removed.last == "paste", "the folder goes after ten clashes")

        fake = FakeFiles()
        placed = []
        answers = [.failed]
        precondition(!PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "a refusal fails")
        precondition(placed.count == 1 && fake.removed == ["paste"], "no retry after a refusal; folder removed")

        fake = FakeFiles()
        fake.writeFails = true
        placed = []
        precondition(!PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "unwritable")
        precondition(placed.isEmpty && fake.removed == ["paste"], "a failed write never reaches Finder")

        fake = FakeFiles()
        fake.folderFails = true
        precondition(!PasteImageSaver.save(Data([1]), at: date, files: fake.files, place: place), "no folder")
        precondition(fake.removed.isEmpty, "nothing to remove")
    }
}
