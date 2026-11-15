# Hidden features

The one list of what Notchcast hides and how. Code stays compiled so upstream harnesses and future rebases retain their sources. `Tests/notchcast-hidden-features-test.swift` pins the hidden tabs and forced-off flags of the table below and fails if a hidden item returns to the Settings sidebar, Settings search or a settings link.

| State | Item | Tab slug | Command IDs | Forced off | Hooks |
| --- | --- | --- | --- | --- | --- |
| Hidden | Extensions | extensions | none | extensionsEnabled | AppSettings, settings tab and search, extension coordinator, hotkeys |
| Hidden | Appearance picker | general (row) | none | appearance, pinned to dark | AppSettings, GeneralSettingsView, SettingsSearchCatalog |
| Hidden | Launcher dragging and snapping | general (row) | none | paletteDraggable | AppSettings, GeneralSettingsView, SettingsSearchCatalog |
| Hidden | Launcher placement | general (row) | none | openOnCursorScreen, stored panel positions | AppSettings, GeneralSettingsView, SettingsSearchCatalog |
| Hidden | Language picker | general (row) | none | AppleLanguages, pinned to English at launch | AppSettings, GeneralSettingsView, SettingsSearchCatalog |

`NotchcastHidden` in `Tinycast/Features/Notchcast/Hidden/` owns the hidden tab set and the English keys of hidden rows; `NotchcastIslandPins` there holds the pinned values; it needs `SettingsTab`, so `notchcast/command-harness-sources.sh` adds it to every harness that compiles `SettingsTab.swift`. On rebase retain the filtering hooks and forced-off getters, even if upstream adds stored defaults or backup restore paths.

- Extensions: `AppSettings.extensionsEnabled` always reads false and ignores writes, including persisted consent and backup restore. `SettingsTab` omits its sidebar row and rejects its settings slug; `SettingsSearchCatalog` omits its search entries. Upstream's `ExtensionManager` publishes no launcher entries while off; `HotKeyManager` exposes no bound extension commands, so a stored binding never registers its chord. `ExtensionCoordinator` rejects store-install links as well as its existing command and link gates. With no entries, upstream's launcher, actions menu and palette accessory have nothing to act on, so they carry no gate; `notchcast-hidden-features-test.swift` pins every hook.
- Appearance: stock colours resolve from `NSAppearance`, so Light or System would put black text on the black island. `AppSettings.appearance` always reads dark and ignores writes, persisted values, backup restore and the `settings.json` mirror; `AppCore.applyAppearance()` therefore sets `NSApp.appearance` to dark from launch.
- Dragging and snapping: `AppSettings.paletteDraggable` always reads false. Snapping and drop guides run only inside a drag session, so no drag means no snapping; there is no snapping setting of its own.
- Placement: `AppSettings.openOnCursorScreen` always reads true, the stock default, and `palettePosition(on:)` returns nil, so a stored panel position from an earlier build is never restored and the island keeps the notch.
- Language: the app is English only. `AppSettings.pinLanguage()` writes `[NotchcastHidden.language]` to `AppleLanguages` at every launch, and `AppSettings.language` reads `.english` and drops writes, so a language carried in by a settings backup or `settings.json` changes nothing and offers no relaunch; the picker row is hidden like the rows below. Upstream's catalogs and translations stay; `Notchcast.xcstrings` carries English only (`fork-strings.md`). Dictation and Quick Action languages are separate settings and stay.
- Hidden rows: the four General rows end in `.notchcastHidden()`, which renders nothing, and `NotchcastHidden.rows` drops their search entries by English key, because titles are localized; the filter applies to the General tab only, so Dictation's own Language row stays searchable.
- Still visible, as in stock: Apple Shortcuts (Commands group), Backup and About (Advanced group, with Support under About's Links), all reachable by slug and in search.
