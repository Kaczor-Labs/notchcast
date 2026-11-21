# Wi-Fi and iPhone bonding

When an iPhone shares Personal Hotspot over USB, torrents and Fast Downloads use Wi-Fi and the iPhone connection at the same time. Part of the Downloads add-on (`Tinycast/Features/Notchcast/Downloads/`); upstream has no feature doc for it, so this page lives with the fork's docs.

## Invariants

- **Nothing outside aria2c changes.** The only effect is one flag, `--multiple-interface=<wifi>,<iphone>`, on an aria2c the add-on starts anyway. No root helper, no system network setting, no route; `BondingInterfaceScanner` only reads SystemConfiguration.
- **A BSD name reaches a command line only as plain ASCII letters and digits.** `BondingPolicy.isUsable` is the one filter; a name with anything else never bonds.
- **Not bonding is never an error.** Option off, an interface missing, a job without aria2c: the job runs exactly as it does without this feature.
- **The iPhone mark means both interfaces are up now.** It shows only for a run that was started on both, and only while both still have a usable IPv4 address; it never promises that traffic flows over the iPhone.
- **Decisions are in `Model/BondingPolicy.swift`** and take the interfaces as a parameter, so `Tests/nc-Downloads-bonding-test.swift` covers them with made-up interfaces.

## Switch

One switch, **Use Wi-Fi and a plugged-in iPhone together**, off by default, at the end of the Downloads switch list. It appears while Torrents or Fast Downloads with aria2c is on. Only Notchcast's own aria2c runs are covered; browsers and other apps stay on Wi-Fi. The torrent-only id `torrentsUseIPhone` is retired, its stored value ignored.

| Id | Applies to |
| - | - |
| `downloadsUseIPhone` | every torrent session, and every Download Video or Download Audio job that runs through aria2c, of any size |

## Which interfaces qualify

- Wi-Fi is the interface whose SystemConfiguration type is IEEE 802.11.
- The iPhone is the interface whose hardware port name contains both "iPhone" and "USB", in any letter case.
- Each needs a usable IPv4 address: not `0.0.0.0`, not loopback, not link-local `169.254/16`, not multicast or above.
- With several candidates, the lowest BSD name wins.

## When a job bonds

- **Torrents:** the interfaces are read when the aria2c session starts (the first torrent). Every torrent of that session shares its flag; a session started without the iPhone stays on Wi-Fi until it ends, even if the iPhone is plugged in later.
- **Downloads:** when the job starts through aria2c (Fast Downloads on and aria2c installed), the interfaces are read once; with the option on and both up, the job bonds, whatever its size. The flag rides in yt-dlp's `--downloader-args` for aria2c. A job that falls back from aria2c to yt-dlp's own downloader is no longer bonded.

## The iPhone mark

- Island: a bonded job's progress line starts with "iPhone · "; while the notice has no percentage yet, its glyph is `iphone`. The notch form shows a percentage only, so it carries no mark.
- Settings › Downloads: each active torrent row shows "Wi-Fi + iPhone". Downloads has no job list.
- `BondingState` rereads the interfaces at most once a second while a mark could show. Unplugging the iPhone removes the mark at the next progress update; aria2c carries on over Wi-Fi.

## Testing

`Tests/nc-Downloads-bonding-test.swift` (filtering, the switch, flag, mark lifetime with a hand-moved clock), `Tests/nc-Downloads-module-test.swift` (`bonding`: the one switch through the module to a fake aria2c session, a fake yt-dlp video job and the island; a stored `torrentsUseIPhone` changes nothing) and `Tests/nc-Downloads-media-test.swift` (the flag on yt-dlp's command line). A real iPhone on USB is a manual check: start a torrent with the option on, look for the mark, unplug, see it go while the download continues.
