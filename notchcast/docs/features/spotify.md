# Spotify

The Spotify add-on (`Tinycast/Features/Notchcast/Spotify/`) feeds the island's Player page and song glance through `IslandPlayerSource` (`SpotifyPlayerPage`); the page and the pill are core's (island-shell.md, "Pages" and "Song glance").

## Player page

- **What Spotify fills in.** `SpotifyPlayerPage.nowPlaying` gives the page the track's id (so a song change keys on it, not on title and artist), the like heart (`liked`, `likePending` while Liked Songs is checked), the volume, `seekable` when Spotify allows a seek, and up to `upNextLimit` (5) songs of Up Next.
- **What the page sends back.** Previous, play/pause and next go to the transport; the heart toggles Liked Songs; a seek bar's fraction becomes a position in the track; a volume bar's fraction becomes Spotify's volume; ↑ and ↓ move the volume by `volumeStep` (10 of 100); Command-R asks Spotify for its state and Liked Songs again.
- **"Expand Player".** The command opens the Player page with `showPage`, pinned and keyed, and closes it again while it shows; with no song loaded it posts "Nothing is playing" instead, so the command never looks broken. It ships with no shortcut; the user records one in its row (addons.md §2).

## Song glance

"Long song names" (Widen, Scroll), a row in Spotify in the Island Options under Settings › Notchcast › Island Content, sets the song's `IslandSongOverflow`, which only the pill without a notch uses.

`Tests/nc-Spotify-module-test.swift` drives the page with a fake transport. Not verified: any of it against a live Spotify.
