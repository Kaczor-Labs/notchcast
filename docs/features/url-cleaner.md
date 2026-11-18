# Clean Copied Links

A Notchcast add-on (`Tinycast/Features/Notchcast/URLCleaner/`, switch `urlCleaner`, off by default, Settings › Launcher Extras). While it is on, a copied link loses its tracking parameters before anything can paste it. It has no command, no hotkey and shows nothing.

## Invariants

- **Only one plain link is ever rewritten.** The clipboard must hold exactly one item, and its text must be one `http` or `https` URL with a host and no whitespace. Each of its types is either in `URLCleanerPolicy.plainLinkTypes` (plain text, URL, URL name) or a type the system does not declare, which is an app's private note about the copy (a browser's source page, Safari's link preview) and is dropped by the rewrite. Rich text, HTML, images, files and several items are left alone, because the rewrite replaces the whole item and would drop content. `untouchableTypes` names the undeclared types that are no private note: secrets, our own marker, legacy file lists and promises.
- **Sensitive copies and our own writes never reach it.** The hook sits in `ClipboardManager.poll()` after the `internalType`, `sensitiveTypes` and disabled-app returns, so those copies end before the cleaner runs; their marker types also fail the plain-link check.
- **One rewrite per copy.** The cleaned link is written with `ClipboardManager.internalType`, so the next poll skips it and the cleaner is not called again.
- **Every byte that stays is the byte that was copied.** `NotchcastLinkCleaner.clean` cuts `name=value` pairs out of the raw string; nothing is re-encoded, reordered or lowercased, and the fragment stays. A query left empty loses its `?`.
- **One tracking list.** `NotchcastLinkCleaner` in `Tinycast/Features/Notchcast/Core/Model/`, shared with Copy Path: `trackingNames` plus every `utm_*` name on every site, and `siteNames` for trackers of one site and its subdomains (`si` on YouTube, `t` on X, where elsewhere they are real parameters). Never add a second list.
- **Derived from Vorssaint.** The tables, the query slicing, the type check and the pasteboard rewrite are adapted from vorssaint/vorssaint-utils (GPL-3.0-or-later); each derived file keeps its notice and has a line in `notchcast/licenses/borrowed.md`.
- **The policy is pure.** `URLCleanerPolicy` imports Foundation only; the pasteboard reaches the module through `URLCleanerSystem`, whose `.live` is the only AppKit in the add-on besides the settings view.

## Flow

1. `URLCleanerModule.start()` sets `ClipboardManager.willCapture`; `stop()` clears it. The static is the one upstream hook (`notchcast/docs/addons.md` §3, H11): `nil` is stock behaviour.
2. Upstream's poll sees a new foreign copy, passes its own skips and calls the hook before it records anything.
3. The module reads the item types and the string (the URL flavour when a copy has no string), asks `URLCleanerPolicy.clean`, and on a change replaces the clipboard with the cleaned link, as a string plus a URL when the copy had one.
4. The poll carries on and records what the clipboard now holds, so clipboard history gets one entry, the cleaned link. The next poll sees our marker and skips.

The cleaner runs inside the clipboard poll, so it works only while Clipboard History is on, and never for an app excluded from history.

## Rules

Three text fields under the switch, stored as strings in the `<bundle id>.notchcast` suite and read on every copy:

| Field | Key | Format |
| --- | --- | --- |
| Extra parameters to remove | `notchcast.urlCleaner.extra` | names separated by commas or spaces |
| Parameters to keep | `notchcast.urlCleaner.kept` | the same; beats every other list, built-in ones included; `utm_*` keeps the whole prefix |
| Per-site rules | `notchcast.urlCleaner.sites` | `host=name,name`, sites separated by `;` |

Names match case-insensitively after percent-decoding. A site rule adds to the built-in ones and covers its host and every subdomain (`x.com` covers `mobile.x.com`, not `notx.com`). A rule without `=` or without a host is ignored.

## Tests

`Tests/nc-URLCleaner-policy-test.swift` covers the policy with fixtures (what is cleaned, what is left alone, rule parsing, the plain-link type check) and drives the module through a fake clipboard the way the poll does: off, on, rich text, settings fields, off again. The real pasteboard and the hook's place in `poll()` have no harness.
