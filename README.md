# Notchcast

A public fork of [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) (AGPL-3.0, see `LICENSE`) with a small patch queue. This branch (`notchcast`, the default branch) holds the queue, the CI and the updater; `main` is generated and never edited by hand.

- `main` = upstream `main` + `patches/series`. `.github/workflows/sync.yml` checks every 10 minutes (and on every push to this branch); when upstream `main` or the queue moved, it applies the queue, builds Debug and runs upstream's `Scripts/run-tests.sh` on a GitHub-hosted `xcode-27` runner, and only when green force-updates `main` (with a lease). That workflow is the only thing that ever force-updates a branch here. The top commit of `main` records `Notchcast-Upstream:` and `Notchcast-Queue:`.
- Every upstream release from `BASELINE_TAG` (in `config.env`) on is rebuilt from its tag + the queue, tested, built Release, signed with `Notchcast Self-Signed` and published here under the same tag, title and prerelease flag, as `Tinycast-<version>.zip` and `.dmg`. Name, bundle id, version and build number are read from upstream's own zip; the fork never has a version of its own. Upstream's tag is mirrored unchanged; the release notes record the queue commit.
- Tests are upstream's full suite except `CI_SKIP_TESTS` in `config.env`: harnesses the hosted VM cannot run (Vision OCR, rendered-text capture). They still have to pass on a Mac before being listed.
- Any failure publishes nothing. It is remembered as `refs/notchcast-failed/<main|release>-<input>-<branch tree>`, so the same input is retried only when upstream moves or this branch changes.

## Patch queue

Features are our own code in this queue; Notchcast uses no Raycast extensions.

`patches/series` lists entries in order: `*.patch` is applied with `git am -3`, `*.sh` runs in the tree and is committed with its first `# ` comment line as the message. Patch 0002 removes upstream's workflows from generated `main` only. Patch 0003 lets the LaunchAgent own starting the app (below).

To change a patch: check out upstream main, apply the series (`bin/notchcast-ci.py apply <tree> main`), edit, `git format-patch --zero-commit -N`, replace the file, commit and push this branch.

## Secrets

Actions secrets: `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` (the self-signed code-signing identity) and `DEPLOY_KEY` (write deploy key `notchcast-actions`; `GITHUB_TOKEN` cannot push commits that touch workflow files). The same material is kept outside git on the maintainer's Mac. The public leaf fingerprint is `SIGN_SHA1` in `config.env`.

Gitleaks runs in CI and as a pre-commit hook: `git config core.hooksPath .githooks` once per clone.

## Installing on a Mac

`bin/install-launchd.sh all` (or `update` / `app` alone) loads two LaunchAgents; logs are in `~/Library/Logs/notchcast/`.

- `notchcast.app` runs `/Applications/Tinycast Beta.app` itself: started at login, restarted after a crash or a Quit (`KeepAlive`, at most every 10 s). It sets `NOTCHCAST_LAUNCHD=1`, so the app keeps its own login item off and its Relaunch only quits (patch 0003): there is never a second instance.
  - Stop: `launchctl bootout gui/$(id -u)/notchcast.app`
  - Start: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/notchcast.app.plist`
- `notchcast.update` runs `bin/notchcast-update.sh` every 30 minutes (needs `gh` logged in). It installs the newest release of the installed app's channel when it is newer than the installed version, or the same version when the installed copy is not ours, after checking bundle id, version and our leaf certificate, then restarts the app agent with `launchctl kickstart -k`. It replaces only the `.app` bundle (the old one goes to the Trash); settings, data and Keychain items stay. After the first switch the in-app updater also takes releases from this repo (patch 0001), because it accepts a bundle signed by the same leaf as the running app. The new signature needs Accessibility to be granted again once.
