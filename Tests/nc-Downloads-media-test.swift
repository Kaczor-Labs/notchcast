// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/CaptionText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsLinks.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaArguments.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaFailure.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/MediaOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/MediaDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TranscriptDownloadRunner.swift
import Foundation

/// Pins yt-dlp arguments, caption text, link picking, and that aria2 is used only when installed and switched on.
@main
struct DownloadsMediaTest {
    static func main() async throws {
        let destination = URL(filePath: "/tmp/media")
        let source = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        let native = MediaArguments.download(source: source, destination: destination, format: .video)
        precondition(!native.contains("--downloader") && !native.contains("--cookies-from-browser"))
        precondition(native.contains("mp4") && native.suffix(2) == ["--", source])
        let audio = MediaArguments.download(source: source, destination: destination, format: .audio,
                                            aria2Path: "/opt/homebrew/bin/aria2c")
        precondition(audio.contains("mp3") && !audio.contains("--cookies-from-browser"))
        precondition(audio.contains("aria2c:-x 16 -s 16 -k 1M --file-allocation=none"))
        precondition(MediaArguments.retryNatively(stderr: "HTTP Error 403: Forbidden", source: source, usedAria2: true))
        precondition(!MediaArguments.retryNatively(stderr: "403", source: source, usedAria2: false))
        precondition(!MediaArguments.retryNatively(stderr: "HTTP Error 403", source: "https://example.com", usedAria2: true))
        let restarted = MediaArguments.download(source: source, destination: destination, format: .video, restart: true)
        precondition(restarted.contains("--no-continue"))
        let manual = MediaArguments.captions(source: source, destination: destination, automatic: false)
        let automatic = MediaArguments.captions(source: source, destination: destination, automatic: true)
        precondition(manual.contains("all,-live_chat") && !manual.contains("en"))
        precondition(automatic.contains(".*-orig") && !automatic.contains("en"))
        precondition(manual.contains("--write-subs") && !manual.contains("--write-auto-subs"))
        precondition(automatic.contains("--write-auto-subs") && !automatic.contains("--write-subs"))
        let manualEnglish = MediaArguments.captions(source: source, destination: destination, automatic: false,
                                                    language: "en-US")
        let automaticEnglish = MediaArguments.captions(source: source, destination: destination, automatic: true,
                                                       language: "en-US")
        precondition(manualEnglish.contains("en-US,en") && automaticEnglish.contains("en-orig,en,en-US"))
        let polish = MediaArguments.captions(source: source, destination: destination, automatic: false, language: "pl")
        let automaticPolish = MediaArguments.captions(source: source, destination: destination, automatic: true,
                                                      language: "pl")
        precondition(polish.contains("pl") && automaticPolish.contains("pl-orig,pl"))
        precondition(manualEnglish.contains("--sleep-subtitles") && automaticEnglish.contains("--sleep-subtitles"))
        let rateLimited = "ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests"
        precondition(MediaArguments.retryCaptions(stderr: rateLimited, wroteCaptions: false))
        precondition(!MediaArguments.retryCaptions(stderr: rateLimited, wroteCaptions: true))
        precondition(!MediaArguments.retryCaptions(stderr: "", wroteCaptions: false))
        let progress = MediaOutput.progress("MEDIA_PROGRESS 4200 NA 10000 18000000.0 105")!
        precondition(progress.fraction == 0.42 && progress.eta == 105)
        let completed = MediaOutput.progress("MEDIA_PROGRESS 629172 629172 NA 2021060.1325613454 NA")!
        precondition(completed.fraction == 1 && completed.eta == nil)
        precondition(completed.bytesPerSecond == 2021060.1325613454)
        precondition(MediaOutput.progress("MEDIA_PROGRESS nan inf NA -1 NA")?.received == nil)
        precondition(MediaOutput.progress("[download] Destination: movie.mp4") == nil)
        let output = MediaOutput.outputPath("MEDIA_FILE \"/tmp/media/movie.mp4\"", destination: destination)
        precondition(output?.lastPathComponent == "movie.mp4")
        precondition(MediaOutput.outputPath("MEDIA_FILE \"/tmp/media/../escape.mp4\"", destination: destination) == nil)
        let rolling = "There are seven new updates in the Claude desktop app, which people are"
            + " calling Claude 2.0, and only four of the"
        let automaticCaptions = """
        WEBVTT
        Kind: captions
        Language: en

        00:00:00.000 --> 00:00:01.790 align:start position:0%
        \u{20}
        There<00:00:00.280><c> are</c><00:00:00.440><c> seven</c><00:00:00.880><c> new</c><00:00:01.160><c> updates</c>
        <00:00:01.600><c> in</c><00:00:01.680><c> the</c>

        00:00:01.790 --> 00:00:01.800 align:start position:0%
        There are seven new updates in the
        \u{20}

        00:00:01.800 --> 00:00:03.350 align:start position:0%
        There are seven new updates in the
        Claude<00:00:02.120><c> desktop</c><00:00:02.600><c> app,</c><00:00:02.880><c> which</c>
        <00:00:03.040><c> people</c><00:00:03.280><c> are</c>

        00:00:03.350 --> 00:00:03.360 align:start position:0%
        Claude desktop app, which people are
        \u{20}

        00:00:03.360 --> 00:00:05.630 align:start position:0%
        Claude desktop app, which people are
        calling<00:00:03.720><c> Claude</c><00:00:04.080><c> 2.0,</c><00:00:04.800><c> and</c><00:00:04.920><c> only</c>
        <00:00:05.120><c> four</c><00:00:05.440><c> of</c><00:00:05.520><c> the</c>
        """.replacingOccurrences(of: "\n<", with: "<")
        precondition(CaptionText.plainText(automaticCaptions, automatic: true) == rolling)
        let manualCaptions = """
        WEBVTT
        Kind: captions
        Language: en

        00:00:00.000 --> 00:00:01.800
        There are seven new updates in the

        00:00:01.800 --> 00:00:03.360
        There are seven new updates in the
        Claude desktop app, which people are

        00:00:03.360 --> 00:00:05.640
        Claude desktop app, which people are
        calling Claude 2.0, and only four of the
        """
        precondition(CaptionText.plainText(manualCaptions, automatic: false) == rolling)
        let repeated = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nNo.\n\n00:00:01.000 --> 00:00:02.000\nNo.\n\n"
            + "00:00:02.000 --> 00:00:03.000\nLet it go\nLet it go"
        precondition(CaptionText.plainText(repeated, automatic: false) == "No. No. Let it go Let it go")
        let thanks = "1\n00:00:00,000 --> 00:00:01,000\nThank you.\n\n2\n00:00:01,000 --> 00:00:02,000\nThank you."
        precondition(CaptionText.plainText(thanks, automatic: false) == "Thank you. Thank you.")
        precondition(CaptionText.plainText("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n \n", automatic: false) == "")
        let escaped = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nyes &amp; no"
        precondition(CaptionText.plainText(escaped, automatic: false) == "yes & no")
        let entities = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nIt&#x27;s &amp; &copy; &ldquo;fine&rdquo; &amp;lt;\n"
        precondition(CaptionText.plainText(entities, automatic: false) == "It's & © “fine” &lt;")
        let srt = "1\n00:00:00,000 --> 00:00:01,000\nHello\n\n2\n00:00:01,000 --> 00:00:02,000\nthere"
        precondition(CaptionText.plainText(srt, automatic: false) == "Hello there")
        precondition(CaptionText.plainText("WEBVTT\n\nNOTE no captions", automatic: true) == "")
        links()
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await runners(root.appending(path: "runners"))
        try await transcripts(root.appending(path: "transcripts"))
        print("Downloads media: arguments, captions, links, aria2 only when installed and on, transcripts")
    }

    private static func links() {
        let copied = """
        Watch https://www.youtube.com/watch?v=abc, then https://example.com/a.
        Again https://www.youtube.com/watch?v=abc and bare example.com/b, ftp://example.com/c,
        https://user:pass@example.com/d and HTTPS://Example.com/e
        """
        precondition(DownloadsLinks.urls(in: copied) == [
            "https://www.youtube.com/watch?v=abc", "https://example.com/a", "HTTPS://Example.com/e"
        ], "links are taken once each, in order, only with an http scheme and no credentials")
        precondition(DownloadsLinks.urls(in: "no links here").isEmpty, "plain text has no links")
    }

    private static func runners(_ root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = root.appending(path: "yt-dlp")
        let script = """
        #!/bin/sh
        dest=''
        mode=media
        language=''
        args="$*"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --paths) shift; dest="$1";;
            --write-subs) mode=manual;;
            --write-auto-subs) mode=auto;;
            --sub-langs) shift; language="$1";;
            --print) shift; [ "$1" != '%(language)s' ] || mode=metadata;;
          esac
          source="$1"
          shift
        done
        if [ "${source##*/}" = none ] && [ "$mode" != metadata ]; then
          :
        elif [ "$mode" = metadata ]; then
          case "$source" in */en|*/de) echo "${source##*/}";; *) echo pl;; esac
        elif [ "$mode" = manual ] && [ "$language" = en ]; then
          printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\nHello\\n' > "$dest/Clip [en].en.vtt"
          echo "ERROR: Unable to download video subtitles for 'en-US': HTTP Error 429: Too Many Requests" >&2
          exit 1
        elif [ "$mode" = manual ] && [ "$language" = de ]; then
          if [ -e "$dest/limited" ]; then
            printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\nHallo\\n' > "$dest/Clip [de].de.vtt"
          else
            touch "$dest/limited"
            echo "ERROR: Unable to download video subtitles for 'de': HTTP Error 429: Too Many Requests" >&2
            exit 1
          fi
        elif [ "$mode" = manual ]; then
          [ "$language" = pl ] || exit 1
          printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\nDzień dobry\\n' > "$dest/Movie [id].pl.vtt"
        elif [ "$mode" = auto ]; then
          exit 1
        elif [ "$mode" = media ]; then
          echo "$args" > "$dest/arguments"
          touch "$dest/movie.mp4"
          printf 'MEDIA_PROGRESS 50 100 NA 10 5\\n'
          printf 'MEDIA_FILE "%s/movie.mp4"\\n' "$dest"
        fi
        """
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "ffmpeg"), withDestinationURL: tool)
        let lookup = DownloadToolLookup(directories: [root, URL(filePath: "/usr/bin"), URL(filePath: "/bin")])
        let context = DownloadRunContext(destination: root, tools: lookup)
        let job = DownloadJob(id: UUID().uuidString, kind: "video", source: "https://example.com/video",
                              title: "Video", state: .waiting, created: Date())
        try await aria2(root, context: context, job: job, enabled: true, expected: false)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "aria2c"), withDestinationURL: tool)
        try await aria2(root, context: context, job: job, enabled: false, expected: false)
        try await aria2(root, context: context, job: job, enabled: true, expected: true)
        let captions = TranscriptDownloadRunner()
        let transcript = try await captions.run(job, context: context)
        let text = try String(contentsOf: transcript!, encoding: .utf8)
        precondition(text == "Dzień dobry")
        precondition(transcript?.lastPathComponent == "Movie [id].txt")
        let second = try await captions.run(job, context: context)
        precondition(second?.lastPathComponent == "Movie [id] (2).txt")
        for (language, expected) in [("en", "Hello"), ("de", "Hallo")] {
            var limited = job
            limited.source = "https://example.com/" + language
            let saved = try await captions.run(limited, context: context)
            let text = try String(contentsOf: saved!, encoding: .utf8)
            precondition(text == expected, "429 exit 1 keeps \(language)")
        }
        var silent = job
        silent.source = "https://example.com/none"
        do {
            _ = try await captions.run(silent, context: context)
            preconditionFailure("a video without captions saves nothing")
        } catch let failure as MediaFailure {
            precondition(failure.detail == "This video has no captions.", "no captions: \(failure.detail)")
        }
    }

    private static func aria2(_ root: URL, context: DownloadRunContext, job: DownloadJob,
                              enabled: Bool, expected: Bool) async throws {
        let output = try await MediaDownloadRunner(format: .video, aria2Enabled: { enabled }).run(job, context: context)
        precondition(output?.lastPathComponent == "movie.mp4")
        let arguments = try String(contentsOf: root.appending(path: "arguments"), encoding: .utf8)
        let installed = FileManager.default.fileExists(atPath: root.appending(path: "aria2c").path)
        precondition(arguments.contains("--downloader") == expected,
                     "aria2 used: \(expected) when installed \(installed) and switched on \(enabled)")
    }

    private static func transcripts(_ root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tool = root.appending(path: "yt-dlp")
        let script = """
        #!/bin/sh
        dest=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --print) echo en; exit 0;;
            --paths) shift; dest="$1";;
          esac
          shift
        done
        printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\n' > "$dest/same.en.vtt"
        /usr/bin/yes caption | /usr/bin/head -c 1000000 >> "$dest/same.en.vtt"
        """
        try script.write(to: tool, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        for round in 0..<12 {
            let folder = root.appending(path: "round-\(round)")
            let context = DownloadRunContext(destination: folder, tools: DownloadToolLookup(directories: [root]))
            let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
                for _ in 0..<12 {
                    group.addTask {
                        let job = DownloadJob(id: UUID().uuidString, kind: "transcript", source: "fixture",
                            title: "Same", state: .waiting, created: Date())
                        return try await TranscriptDownloadRunner().run(job, context: context)!
                    }
                }
                var urls = [URL]()
                for try await url in group { urls.append(url) }
                return urls
            }
            precondition(Set(outputs).count == 12, "Concurrent transcripts overwrote each other")
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            precondition(files.count == 12)
        }
    }
}
