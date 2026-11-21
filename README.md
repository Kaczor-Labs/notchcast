<!-- Generated: the root README.md is a copy of notchcast/README.public.md made by `notchcast/ci.py regenerate`.
     Edit notchcast/README.public.md. Links use repository-root paths (/LICENSE) so they work in both places. -->

# Notchcast

[![Release](https://img.shields.io/github/v/release/kaczordodgers/notchcast)](https://github.com/kaczordodgers/notchcast/releases/latest)
[![Sync](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml/badge.svg)](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](/LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-lightgrey)

Notchcast is a macOS launcher that lives in an island at the top of your screen, around the notch or where a notch would be. It is [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, the native launcher with clipboard history, hotkeys, snippets, window management and system tools, plus our own commits on top: the island that replaces Tinycast's floating palette and menu-bar icons, and a set of add-ons for keyboard, display, sound, capture and downloads. Every upstream change is replayed under our commits once its review passed, so Notchcast stays current with Tinycast.

**Status:** in use; a snapshot is published from every green `main`.

[Download](https://github.com/kaczordodgers/notchcast/releases) · [Use it](#use-it) · [Contribute](#where-things-are)

## Install

You need macOS 26 or later on Apple silicon.

1. Open [Releases](https://github.com/kaczordodgers/notchcast/releases) and download `Notchcast-<version>.dmg` from the newest `snapshot` pre-release. Snapshots are built from every green `main`; the releases without `snapshot` rebuild each upstream Tinycast release with our commits.
2. Drag Notchcast to Applications.
3. Builds are signed with our own self-signed certificate and are not notarized, so remove the quarantine flag once: `xattr -dr com.apple.quarantine /Applications/Notchcast.app`
4. Open Notchcast and grant Accessibility when asked. Turn on **Launch at login** in Settings › General if you want it at every login.

Notchcast has its own bundle id (`app.notchcast`), URL scheme (`notchcast://`) and data, so it runs beside Tinycast.

## Update

The in-app updater stays off in Notchcast. To keep a Mac current, clone this repo and run `/bin/bash notchcast/install-launchd.sh update` once (needs the `gh` CLI logged in). Every 30 minutes it installs the newest snapshot into `/Applications`, after it checks the bundle id, version and our signing certificate. It keeps one previous copy for rollback, restarts Notchcast only if it was running, and never touches settings or data. The script itself does not update: after pulling this repo, run the same command again to update it. Turn off **Automatically check for updates** in Notchcast's settings to pause it. Without the script, download a newer snapshot by hand and repeat steps 2 and 3. Details: [Installing on a Mac](/notchcast/README.md#installing-on-a-mac).

## Use it

<!-- features:start -->

- **The island.** At rest it is a small pill at the top of the screen, or the notch itself. Press your global shortcut and it opens into the launcher. Rest the pointer on it and it opens what it shows: the meeting's title, a status's name, a download's title (turn this off with Open on hover in Settings). Click it, or right-click it, for its menu with Settings and Quit. When your calendar has a meeting coming up, the pill shows a countdown (and its title, without a notch), and grows for a moment when it is time to join. Notices, add-on status and the volume level also show in the island.
- **The launcher.** Everything Tinycast does: app and command search, clipboard history, snippets, quicklinks, calculator with units and currencies, emoji, file and menu-bar search, window management, layouts and rooms, notes, calendar, dictionary, Quick AI and AI chat, custom commands and deeplinks. Feature docs: [docs/features](/docs/features).
- **Look per display.** Each display's island is Black or Frosted (glass). A display you never set is Black when it has a notch and Frosted when it has none. Change it in Settings › Notchcast › Island.
- **Settings › Notchcast.** One tab per area, each add-on with its own switch; an add-on's tab shows only while that add-on is in the build.
  <!-- addon-tabs:start -->
  - **Island**: look, outline when open, open on hover, position on displays without a notch, show in screenshots and videos.
  - **Agents**: Agents in the Island, a page with how much of each Claude and Codex plan is left.
  - **Keyboard & Mouse**: hide with ⌘M, Show Desktop with F3, Quit Protection, trackpad middle click, Paste Plain Text.
  - **Display & Sound**: stop Apple Music opening on media keys, the play key resumes Spotify if you played it last, brightness keys for every display, volume in the island, AirPods and Beats noise control from the launcher, Spotify in the Island through Soloist.
  - **Capture**: screenshots of an area, window or display, and an editor to mark one up with arrows, shapes, highlights, text, pixelation and a crop before copying, saving or dragging it out, screen recordings you trim before keeping them, copy a color from anywhere on the screen.
  - **Launcher Extras**: small commands for passwords, short links and AirDrop, Copy Path for Finder files, browser links and documents, your own shell scripts with the result in the island, countdowns and alarms that tick in the island, clean tracking parameters from copied links (with Clipboard History on).
  - **Downloads**: video, audio, transcripts and webpages from clipboard links, with optional aria2c and transcription into a local folder; downloads and torrents can use Wi-Fi and a USB-tethered iPhone together; optionally a copy of each note in a Markdown folder you choose, where PDF, HTML, audio and video files added while the option is on become notes and their originals go to the Trash, Taildrop the Finder selection to another of your devices, ⌘V in a Finder window saves a copied image there as a PNG, extract archives in place with HatchZip.
  - **Power**: a warning in the island when the startup disk is nearly full.
  - **Mac Tweaks**: turn off iPhone auto backups, back up your settings on change and once a day, move files in Finder with ⌘X and ⌘V and rename them in the launcher, Day in the Island, a page with the weather, your market quotes and today’s events, Touch ID for sudo and tools for processes, the network, IP addresses and Wi-Fi passwords, System in the Island, a page with CPU, memory, disk and network that warns when one runs hot.
  <!-- addon-tabs:end -->
- **Add-on commands** are ordinary launcher commands: search them, and give them an alias, a hotkey or Show in launcher on the command's row in its Notchcast tab.

Notchcast is English only and Dark only.

Settings can be mirrored to `~/.config/app.notchcast/settings.json`; see [settings-file.md](/docs/features/settings-file.md).

<!-- features:end -->

## Dev builds

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/kaczordodgers/notchcast.git
cd notchcast
xcodegen generate
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build
```

A Debug build is a separate app: `Notchcast Dev.app`, bundle id `app.notchcast.dev`, with its own settings, data and permissions, and its name in the menus, About and dialogs. It never replaces or collides with the installed Notchcast. A copy built with its own suffix, such as `app.notchcast.dev.mytask`, names itself `Notchcast Dev mytask` ([fork-strings.md](/notchcast/docs/fork-strings.md#channel-name)). Debug builds sign ad-hoc, so each rebuild loses its Accessibility grant; [signing.md §1](/docs/signing.md) sets up a local identity that keeps it. More: [development.md](/docs/development.md).

## Where things are

The Xcode project, target and source folders use the name `Tinycast`.

```text
Tinycast/                     app sources
  Features/<Name>/            upstream features, one folder each
  Features/Island/            the island: engine, shell, meeting glance
  Features/Notchcast/         our add-ons, one folder each, plus Core and Hidden
  Features/Notchcast/NotchcastRegistry.swift   one line per add-on
Tests/                        standalone harnesses, no XCTest; ours are nc-<Folder>-*.swift and notchcast-*.swift
Scripts/                      upstream's build, test and lint scripts
docs/                         upstream's developer and feature docs
notchcast/                    fork tooling: sync, CI, landing, checks, install and update
notchcast/docs/               fork docs
.github/workflows/            CI: PR, Sync, Snapshot, Main harnesses, Design, Leaks, CodeQL
project.yml                   XcodeGen input; Tinycast.xcodeproj is generated from it
```

The dev loop:

- Test locally with `./Scripts/run-tests.sh` (all harnesses, ours included) or `./Scripts/run-tests.sh <harness>`, and `./Scripts/lint.sh`. See [testing.md](/docs/testing.md).
- The maintainer proves a pushed branch with `python3 notchcast/notchcast-ci.py --repo . --keeper`, which waits for GitHub's harness verdict on it.
- PRs open as drafts. Maintainers land them only with `notchcast/land.sh <pr>`, which tests the merge onto `main` and squash-merges it.
- Sync replays our commits onto each new upstream `main` once the maintainer's review of the upstream diff passed, and Snapshot publishes every green `main`. Generated files (`README.md`, the Xcode project) are rebuilt by CI; edit `notchcast/README.public.md` and `project.yml` instead.

Read before you change things:

| Doc | For |
| --- | --- |
| [AGENTS.md](/AGENTS.md) | agents: rules, posture, definition of done |
| [notchcast/README.md](/notchcast/README.md) | maintainers: sync, CI, landing, releases, installing on a Mac |
| [addons.md](/notchcast/docs/addons.md) | writing an add-on: one folder that declares itself |
| [island-shell.md](/notchcast/docs/island-shell.md) | how the island works |
| [design-system.md](/notchcast/docs/design-system.md) | Notchcast's look; upstream's is [ui.md](/docs/ui.md) |
| [hotspots.md](/notchcast/docs/hotspots.md) | upstream files to avoid touching |
| [architecture.md](/docs/architecture.md), [standards.md](/docs/standards.md) | upstream's wiring and Swift rules |

Contributing: [CONTRIBUTING.md](/.github/CONTRIBUTING.md). Security reports: [SECURITY.md](/.github/SECURITY.md). Bugs go in [our issues](https://github.com/kaczordodgers/notchcast/issues), not upstream's.

## License

GNU Affero General Public License v3.0 or later, the same as Tinycast. See [LICENSE](/LICENSE). Tinycast is Copyright (C) 2026 Abue Ammar; Notchcast's changes are released under the same license.

Notchcast is a modified version of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, as the AGPL (section 5a) requires us to state: our changes are the commits on top of upstream `main`, and [notchcast/README.md](/notchcast/README.md) describes how they are kept and rebuilt. Third-party material and its licences are listed in [NOTICE.md](/NOTICE.md); code our add-ons borrow is listed in [borrowed.md](/notchcast/licenses/borrowed.md).
