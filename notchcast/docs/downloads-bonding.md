# Wi-Fi and iPhone bonding

When an iPhone shares Personal Hotspot over USB, big downloads and torrents use Wi-Fi and the iPhone connection at the same time. Part of the Downloads add-on (`Tinycast/Features/Notchcast/Downloads/`); upstream has no feature doc for it, so this page lives with the fork's docs.

## Invariants

- **Nothing outside aria2c changes.** The only effect is one flag, `--multiple-interface=<wifi>,<iphone>`, on an aria2c the add-on starts anyway. No root helper, no system network setting, no route; `BondingInterfaceScanner` only reads SystemConfiguration.
- **A BSD name reaches a command line only as plain ASCII letters and digits.** `BondingPolicy.isUsable` is the one filter; a name with anything else never bonds.
- **Not bonding is never an error.** Option off, an interface missing, a small or unsized download: the job runs exactly as it does without this feature.
- **The iPhone mark means both interfaces are up now.** It shows only for a run that was started on both, and only while both still have a usable IPv4 address; it never promises that traffic flows over the iPhone.
- **Decisions are in `Model/BondingPolicy.swift`** and take the interfaces as a parameter, so `Tests/nc-Downloads-bonding-test.swift` covers them with made-up interfaces.

## Switches

Both are named **Use Wi-Fi and a plugged-in iPhone together** and are off by default.

| Id | Needs | Applies to |
| - | - | - |
| `torrentsUseIPhone` | Torrents | every torrent |
| `downloadsUseIPhone` | Fast Downloads with aria2c | a Download Video or Download Audio job larger than 200 MB |

## Which interfaces qualify

- Wi-Fi is the interface whose SystemConfiguration type is IEEE 802.11.
- The iPhone is the interface whose hardware port name contains both "iPhone" and "USB", in any letter case.
- Each needs a usable IPv4 address: not `0.0.0.0`, not loopback, not link-local `169.254/16`, not multicast or above.
- With several candidates, the lowest BSD name wins.

## When a job bonds

- **Torrents:** the interfaces are read when the aria2c session starts (the first torrent). Every torrent of that session shares its flag; a session started without the iPhone stays on Wi-Fi until it ends, even if the iPhone is plugged in later.
- **Downloads:** only when the option is on and both interfaces are up, the job first asks yt-dlp for the size (`MediaArguments.size`, no download); when yt-dlp cannot tell, as for a direct file link, `DownloadSizeProbe` asks the server with one `HEAD` request on a private ephemeral session. Larger than 200 MB (200,000,000 bytes) bonds; smaller, exactly 200 MB or unknown does not. The flag rides in yt-dlp's `--downloader-args` for aria2c. A job that falls back from aria2c to yt-dlp's own downloader is no longer bonded.

## The iPhone mark

- Island: a bonded job's progress line starts with "iPhone · "; while the notice has no percentage yet, its glyph is `iphone`. The notch form shows a percentage only, so it carries no mark.
- Settings › Downloads: each active torrent row shows "Wi-Fi + iPhone". Downloads has no job list.
- `BondingState` rereads the interfaces at most once a second while a mark could show. Unplugging the iPhone removes the mark at the next progress update; aria2c carries on over Wi-Fi.

## Testing

`Tests/nc-Downloads-bonding-test.swift` (filtering, threshold, flag, mark lifetime with a hand-moved clock), `Tests/nc-Downloads-module-test.swift` (`bonding`: the switch through the module to a fake aria2c session and the island) and `Tests/nc-Downloads-media-test.swift` (the size question and the flag on yt-dlp's command line). A real iPhone on USB is a manual check: start a torrent with the option on, look for the mark, unplug, see it go while the download continues.
