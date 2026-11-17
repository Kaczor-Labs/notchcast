<!-- Source of the root README.md: `notchcast/ci.py regenerate` copies this file there, so edit this one.
     Links use repository-root paths (/LICENSE) so they work in both places. Maintainer docs: notchcast/README.md. -->

# Notchcast

[![Release](https://img.shields.io/github/v/release/kaczordodgers/notchcast)](https://github.com/kaczordodgers/notchcast/releases/latest)
[![Sync](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml/badge.svg)](https://github.com/kaczordodgers/notchcast/actions/workflows/sync.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](/LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-lightgrey)

A native macOS launcher with clipboard history, hotkeys, snippets, window management and system tools in one app.

Notchcast is a modified fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar. It is upstream Tinycast plus our own changes on top, rebuilt automatically whenever upstream moves. See [Credits](#credits).

[Download](https://github.com/kaczordodgers/notchcast/releases) · [Build from source](#build-from-source) · [Maintaining the fork](/notchcast/README.md)

## Features

<!-- features:start -->

Notchcast keeps upstream's features: app and command search, clipboard history, snippets, quicklinks, calculator with units and currencies, emoji picker, file search, menu bar search, window management, window layouts and rooms, notes, calendar and meeting join, camera, dictionary, Quick AI and AI chat with MCP servers, quick actions on selected text, custom commands, backups, uninstall apps, global hotkeys with a Hyper key, and deeplinks. Upstream's docs are in [docs/features](/docs/features).

Hidden in Notchcast (the code stays): Raycast extensions. The reason: [hidden.md](/notchcast/docs/hidden.md).

<!-- features:end -->

## Requirements

- macOS 26 or later, Apple silicon (arm64 builds only).
- Accessibility access for keys and window features; some features also ask for further permissions when you use them.

## Install

1. Download `Notchcast-<version>.dmg` from [Releases](https://github.com/kaczordodgers/notchcast/releases). The newest non-pre-release follows upstream's latest release; the `snapshot` pre-releases are built from every green `main`.
2. Drag Notchcast to Applications.
3. Releases are signed with our own self-signed certificate and are not notarized, so remove the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Notchcast.app
   ```

4. Open Notchcast and grant Accessibility when asked.

Notchcast uses its own bundle id (`app.notchcast`) and URL scheme (`notchcast://`), so it can run beside Tinycast.

## Quickstart

1. Onboarding asks for the global shortcut that opens the launcher; change it later in **Settings → General → Global Shortcuts**.
2. Press it and type: an app, a command such as `Clipboard History`, or a sum such as `12*7`.

Settings can also be mirrored to `~/.config/app.notchcast/settings.json`; see [docs/features/settings-file.md](/docs/features/settings-file.md).

## Build from source

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/kaczordodgers/notchcast.git
cd notchcast
xcodegen generate
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build
```

The project, target and source folders keep upstream's `Tinycast` names so our commits rebase cleanly. Debug builds are `Notchcast Dev.app` (`app.notchcast.dev`). They sign ad-hoc, so headless Xcode builds them anywhere, but a local run loses its Accessibility grant on each rebuild; to keep it, pass `CODE_SIGN_IDENTITY="Tinycast Self-Signed"` after creating that identity once with [docs/signing.md §1](/docs/signing.md). Add `CODE_SIGNING_ALLOWED=NO` for a build-only check. Release signing is unchanged. More: [docs/development.md](/docs/development.md).

### Tests

```sh
./Scripts/run-tests.sh            # upstream's harnesses plus ours (no XCTest)
./Scripts/run-tests.sh calc-test  # one harness
./Scripts/lint.sh
```

Details: [docs/testing.md](/docs/testing.md).

### Project structure

```text
Tinycast/              app sources (upstream's name, kept for clean rebases)
  Features/<Name>/     one folder per feature
  Features/Notchcast/  fork code: the hidden upstream tabs
Tests/                 runnable harnesses (Tests/notchcast-*-test.swift are ours)
Scripts/               upstream's build, test and lint scripts
docs/                  upstream's developer docs
notchcast/             fork tooling and docs: sync, landing, checks, notchcast/docs/
project.yml            XcodeGen input for Tinycast.xcodeproj
```

Contributing: [CONTRIBUTING.md](/.github/CONTRIBUTING.md). Security reports: [SECURITY.md](/.github/SECURITY.md).

## Credits

Notchcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar, and it would not exist without it. This is a modified version, as the AGPL (section 5a) requires us to state: our changes are the commits on top of upstream `main`, and [notchcast/README.md](/notchcast/README.md) describes how they are kept and rebuilt. Bugs in Notchcast belong in [our issues](https://github.com/kaczordodgers/notchcast/issues), not upstream's.

Third-party material and its licences are listed in [NOTICE.md](/NOTICE.md).

## License

GNU Affero General Public License v3.0 or later, the same as Tinycast. See [LICENSE](/LICENSE). Tinycast is Copyright (C) 2026 Abue Ammar; Notchcast's changes are released under the same license.
