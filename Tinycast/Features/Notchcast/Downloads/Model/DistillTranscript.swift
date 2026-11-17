import Foundation

/// A Distill transcript: chunk texts in order, each line optionally led by its chunk's start time.
nonisolated enum DistillTranscript {
    struct Segment: Equatable, Sendable {
        let start: TimeInterval
        let text: String
    }

    static func text(_ segments: [Segment], times: Bool) -> String {
        let lines = segments.compactMap { segment -> String? in
            let words = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            return times ? "\(clock(segment.start)) \(words)" : words
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, min(seconds, Double(Int32.max)))) : 0
        return String(format: "[%02d:%02d:%02d]", whole / 3600, whole / 60 % 60, whole % 60)
    }

    /// The file name without its `.txt`, safe as one path component.
    static func stem(channel: String?, title: String) -> String {
        let parts = [channel, title].compactMap { $0.map(clean) }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Untitled" : parts.joined(separator: " - ")
    }

    /// ffmpeg cuts the audio into `seconds`-long 16 kHz mono WAV files named in playback order.
    static func chunkArguments(input: URL, seconds: Int, folder: URL) -> [String] {
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", input.path, "-map", "0:a:0", "-vn",
         "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-f", "segment", "-segment_time", String(seconds),
         folder.appending(path: "chunk-%05d.wav").path]
    }

    private static func clean(_ text: String) -> String {
        let replaced = String(text.replacingOccurrences(of: ": ", with: " - ").unicodeScalars.map { scalar -> Character in
            "/:\\<>\"|?*".unicodeScalars.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
                ? "-" : Character(scalar)
        })
        let spaced = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        for character in spaced {
            guard result.utf8.count + String(character).utf8.count <= 100 else { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}
