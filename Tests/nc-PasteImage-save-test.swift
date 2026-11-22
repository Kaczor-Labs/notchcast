// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Service/PasteImageSystem*.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift

import AppKit
import Synchronization

enum Paster { static let tinycastEventTag: Int64 = 0x54494E59 }

@main
enum PasteImageSaveTests {
    enum Step: String, CaseIterable {
        case beforeStart, target, exists, decode, location, write, select
    }

    static func main() async {
        let steps = Array(Step.allCases.dropFirst())
        var failures: [String] = []
        for cancelAt in Step.allCases {
            let called = Mutex<[Step]>([])
            let logs = Mutex<[String]>([])
            let clip = PasteImageClip(data: Data([1]), isPNG: true)

            @Sendable func record(_ step: Step) {
                called.withLock { $0.append(step) }
                if cancelAt == step { withUnsafeCurrentTask { $0?.cancel() } }
            }

            let result = await Task {
                if cancelAt == .beforeStart { withUnsafeCurrentTask { $0?.cancel() } }
                return await PasteImageFinder.save(
                    clip, at: Date(timeIntervalSince1970: 0),
                    send: { event in
                        switch event.eventID {
                        case 0x67657464: // getd
                            record(.target)
                            return (nil, -1728)
                        case 0x646f6578: // doex
                            record(.exists)
                            event.setParam(NSAppleEventDescriptor(boolean: false), forKeyword: 0x2d2d2d2d)
                            return (event, 0)
                        case 0x736c6374: // slct
                            record(.select)
                            return (nil, cancelAt == .select ? -1712 : 0)
                        default:
                            preconditionFailure("Unexpected Apple event")
                        }
                    },
                    png: { clip in
                        record(.decode)
                        return clip.data
                    },
                    insertionLocation: {
                        record(.location)
                        return ("/fake", 0)
                    },
                    files: PasteImageFiles(write: { _, _ in record(.write) }, remove: { _ in
                        preconditionFailure("Unexpected removal")
                    }),
                    logError: { message in logs.withLock { $0.append(message) } }
                )
            }.value

            let expected = Array(steps.prefix { $0 != cancelAt }) + [cancelAt]
            let expectedCalls = cancelAt == .beforeStart ? [] : expected
            let calls = called.withLock { $0 }
            let messages = logs.withLock { $0 }
            if calls != expectedCalls || !messages.isEmpty || result != nil {
                failures.append(
                    "cancel at \(cancelAt.rawValue): steps \(calls.map(\.rawValue)), logs \(messages), " +
                    "result \(String(describing: result))"
                )
            }
        }
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("nc-PasteImage-save-test: PASS")
    }
}
