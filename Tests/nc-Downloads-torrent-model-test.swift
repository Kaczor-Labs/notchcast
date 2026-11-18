// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentBencode.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentMetainfo.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentInput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentStatus.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentJobPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentIslandPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/Aria2Arguments.swift
import Foundation

/// Bencode, info hashes, magnet hashes, clipboard inputs, job transitions and the no-peers timeout.
@main
struct TorrentModelTest {
    static func main() {
        bencode()
        metainfo()
        magnets()
        inputs()
        transitions()
        island()
        arguments()
        print("Torrent model: bencode, info hash, magnet hash, inputs, job states, no-peers timeout, island line")
    }

    static let info = "d6:lengthi5e4:name5:a.txt12:piece lengthi16384e6:pieces20:" + String(repeating: "x", count: 20) + "e"
    static let torrent = Data(("d8:announce14:http://a/b/ann4:info" + info + "e").utf8)

    private static func bencode() {
        func parse(_ text: String) -> TorrentBencode? { try? TorrentBencode.parse(Data(text.utf8)).value }
        expect(parse("i42e") == .integer(42) && parse("i-7e") == .integer(-7) && parse("i0e") == .integer(0),
               "integers")
        for bad in ["i-0e", "i03e", "ie", "i1", "i9999999999999999999999e", "03:abc", "4:abc", "l", "d1:ai1e"] {
            expect(parse(bad) == nil, "malformed \(bad) is refused")
        }
        expect(parse("d1:ai1e1:ai2ee") == nil, "a duplicate key is refused")
        expect(parse("i1ei2e") == nil, "trailing bytes are refused")
        expect(parse(String(repeating: "l", count: 100) + String(repeating: "e", count: 100)) == nil,
               "nesting past the depth cap is refused")
        expect(parse("l4:spami3ee") == .list([.bytes(Data("spam".utf8)), .integer(3)]), "a list")
        expect(parse("d3:cow3:mooe")?["cow"]?.text == "moo", "a dictionary")
        let parsed = try? TorrentBencode.parse(torrent)
        expect(parsed?.info.flatMap { String(bytes: torrent[$0], encoding: .utf8) } == info, "the info range is exact")
    }

    private static func metainfo() {
        let metainfo = TorrentMetainfo(data: torrent)
        expect(metainfo?.infoHash == "0aed067d7c18858488c371d1434c2fa4aee0699a", "the info hash is SHA-1 of info")
        expect(metainfo?.name == "a.txt", "the name comes from info")
        expect(TorrentMetainfo(data: Data("d8:announce3:abce".utf8)) == nil, "no info dictionary, no torrent")
        expect(TorrentMetainfo(data: Data("d4:infoi1ee".utf8)) == nil, "info must be a dictionary")
        expect(TorrentMetainfo(data: Data(repeating: 0x20, count: TorrentMetainfo.maxBytes + 1)) == nil,
               "over 16 MB is refused")
    }

    private static func magnets() {
        let hex = "C12FE1C06BBA254A9DC9F519B335AA7C1367A88A"
        let magnet = TorrentMagnet("magnet:?xt=urn:btih:\(hex)&dn=Big+Buck&tr=udp://t:1")
        expect(magnet?.infoHash == hex.lowercased(), "hex info hash, lowercased")
        expect(magnet?.name == "Big Buck", "dn is the name, + read as a space")
        expect(TorrentMagnet("magnet:?xt=urn:btih:YEX6DQDLXISUVHOJ6UM3GNNKPQJWPKEK")?.infoHash == hex.lowercased(),
               "base32 decodes to the same hash")
        expect(TorrentMagnet("magnet:?dn=x&xt=urn:sha1:abc&xt=urn:btih:\(hex)")?.infoHash == hex.lowercased(),
               "the btih topic is found among others")
        for bad in ["magnet:?xt=urn:btih:123", "magnet:?xt=urn:btih:" + String(repeating: "g", count: 40),
                    "magnet:?dn=x", "https://x/?xt=urn:btih:\(hex)", "magnet:?xt=urn:btih:YEX6DQDLXISUVHOJ6UM3GNNKPQJWPKE1"] {
            expect(TorrentMagnet(bad) == nil, "\(bad) is refused")
        }
    }

    private static func inputs() {
        let text = """
        magnet:?xt=urn:btih:abc
          /srv/me/Downloads/a.torrent
        https://example.com/x.torrent
        /srv/me/notes.txt
        https://example.com/page
        magnet:?xt=urn:btih:abc
        file:///tmp/b.TORRENT
        """
        expect(TorrentInput.parse(clipboard: text) == [
            .magnet("magnet:?xt=urn:btih:abc"), .file(URL(filePath: "/srv/me/Downloads/a.torrent")),
            .remote(URL(string: "https://example.com/x.torrent")!), .file(URL(string: "file:///tmp/b.TORRENT")!),
        ], "one per line, de-duplicated, only torrents")
        expect(TorrentInput.classify(URL(string: "tinycast://settings")!) == nil, "other URLs are not claimed")
        expect(TorrentInput.classify(URL(string: "ftp://x/a.torrent")!) == nil, "only http and https are fetched")
    }

    private static func transitions() {
        let start = Date(timeIntervalSince1970: 1_000)
        let downloads = URL(filePath: "/srv/me/Downloads", directoryHint: .isDirectory)
        var job = TorrentJob(input: .magnet("m"), infoHash: "h", name: "h", started: start)
        job.gid = "meta"
        func advance(_ status: TorrentStatus, at seconds: TimeInterval, keepSharing: Bool = false) {
            job = TorrentJobPolicy.advance(job, with: status, now: start.addingTimeInterval(seconds),
                                           keepSharing: keepSharing, destination: downloads)
        }
        advance(TorrentStatus(status: "active"), at: 1)
        expect(job.state == .findingPeers, "no peers, no bytes: finding peers")
        advance(TorrentStatus(status: "complete", followedBy: ["real"]), at: 2)
        expect(job.gid == "real" && job.state == .findingPeers, "a magnet's metadata job is followed to its download")
        advance(TorrentStatus(status: "active", total: 100, connections: 0), at: 599)
        expect(job.state == .findingPeers, "under ten quiet minutes the job waits")
        advance(TorrentStatus(status: "active", total: 100), at: 602)
        expect(job.state == .failed("No peers found in 10 minutes."), "ten quiet minutes fail the job")

        job = TorrentJob(input: .magnet("m"), infoHash: "h", name: "h", started: start)
        advance(TorrentStatus(status: "active", completed: 10, total: 100, speed: 5, connections: 3, seeders: 2,
                              name: "Big Buck"), at: 1)
        expect(job.state == .downloading && job.name == "Big Buck" && job.peers == 3 && job.seeders == 2,
               "bytes and peers: downloading, named")
        expect(job.secondsLeft == 18 && job.fraction == 0.1, "time left and progress")
        advance(TorrentStatus(status: "active", completed: 10, total: 100, connections: 1), at: 900)
        expect(job.state == .downloading, "connected peers keep a stalled job alive")
        let files = ["/srv/me/Downloads/Big/a.mkv", "/srv/me/Downloads/../evil", "relative", "/tmp/x"]
        advance(TorrentStatus(status: "active", completed: 100, total: 100, isSeeding: true, files: files),
                at: 901, keepSharing: true)
        expect(job.state == .sharing, "complete with keep-sharing: sharing")
        expect(job.files == [URL(filePath: "/srv/me/Downloads/Big/a.mkv")], "only files inside Downloads are kept")
        advance(TorrentStatus(status: "complete", completed: 100, total: 100), at: 902, keepSharing: true)
        expect(job.state == .finished && job.speed == 0, "ratio reached: finished")
        advance(TorrentStatus(status: "error", error: "x"), at: 903)
        expect(job.state == .finished, "a finished job stays finished")

        job = TorrentJob(input: .magnet("m"), infoHash: "h", name: "h", started: start)
        advance(TorrentStatus(status: "active", completed: 100, total: 100, isSeeding: true), at: 1)
        expect(job.state == .downloading, "without keep-sharing a complete job waits for aria2c to stop it")
        advance(TorrentStatus(status: "error", error: ""), at: 2)
        expect(job.state == .failed("aria2c stopped this download."), "an error without a message gets one")
        job = TorrentJob(input: .magnet("m"), infoHash: "h", name: "h", started: start)
        advance(TorrentStatus(status: "removed"), at: 1)
        expect(job.state == .cancelled, "removed: cancelled")
    }

    private static func island() {
        let start = Date(timeIntervalSince1970: 0)
        var policy = TorrentIslandPolicy()
        var job = TorrentJob(input: .magnet("m"), infoHash: "h", name: "Big Buck", started: start)
        expect(policy.update([job]).progress?.text == "Big Buck · Finding peers", "finding peers line")
        job.state = .downloading
        job.completed = 42
        job.total = 100
        job.speed = 1_000_000
        let progress = policy.update([job]).progress
        expect(progress?.fraction == 0.42 && progress?.text.hasPrefix("Big Buck · 42% · ") == true
               && progress?.text.hasSuffix(" left") == true, "name, percent, speed and time left")
        job.state = .finished
        let done = policy.update([job])
        expect(done.progress == nil && done.finished == [job], "a finish is reported once")
        expect(policy.update([job]).finished.isEmpty, "and never again")
        var failed = TorrentJob(input: .magnet("n"), infoHash: "i", name: "x", started: start)
        failed.state = .failed("This torrent is already running.")
        expect(policy.update([job, failed]).failed == [failed], "a failure is reported")
        expect(TorrentIslandPolicy.failure(failed) == "x: This torrent is already running.", "with its reason")
    }

    private static func arguments() {
        let arguments = Aria2Arguments(port: 6800, secret: "s", stateDirectory: URL(filePath: "/state"),
                                       downloads: URL(filePath: "/dl"), parent: 42, extra: ["--multiple-interface=en0"])
        let line = arguments.arguments
        for flag in ["--rpc-listen-all=false", "--disable-ipv6=true", "--stop-with-process=42",
                     "--rpc-listen-port=6800", "--file-allocation=none", "--continue=true", "--allow-overwrite=false",
                     "--check-integrity=true", "--dht-file-path=/state/dht.dat", "--dir=/dl", "--conf-path=/state/session.conf"] {
            expect(line.contains(flag), "aria2c runs with \(flag)")
        }
        expect(line.last == "--multiple-interface=en0", "extra arguments come last")
        expect(!line.contains { $0.contains("secret") } && arguments.configurationText == "rpc-secret=s\n",
               "the RPC secret is never on the command line")
        expect(Aria2Arguments.options(keepSharing: false) == ["seed-time": "0"], "no sharing: stop at completion")
        expect(Aria2Arguments.options(keepSharing: true) == ["seed-ratio": "1.0"], "keep sharing: ratio 1.0")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        print("FAIL: \(message)")
        exit(1)
    }
}
