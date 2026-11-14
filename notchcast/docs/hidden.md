# Hidden features

The one list of what Notchcast hides and how. Code stays compiled so upstream harnesses and future rebases retain their sources. `Tests/notchcast-hidden-features-test.swift` pins the hidden tabs and forced-off flags of the table below and fails if a hidden item returns to the Settings sidebar, Settings search or a settings link.

| State | Item | Tab slug | Command IDs | Forced off | Hooks |
| --- | --- | --- | --- | --- | --- |
| Hidden | Extensions | extensions | none | extensionsEnabled | AppSettings, AppCore startup, extension coordinator, launcher and hotkeys |

`NotchcastHidden` in `Tinycast/Features/Notchcast/Hidden/` owns the hidden tab set; it needs `SettingsTab`, so `notchcast/command-harness-sources.sh` adds it to every harness that compiles `SettingsTab.swift`. On rebase retain the filtering hooks and forced-off getters, even if upstream adds stored defaults or backup restore paths.

- Extensions: `AppSettings.extensionsEnabled` always reads false and ignores writes, including persisted consent and backup restore. `SettingsTab` omits its sidebar row and rejects its settings slug; `SettingsSearchCatalog` omits its search entries. Upstream's `ExtensionManager` publishes no launcher entries while off; `HotKeyManager` exposes no bound extension commands, and `LauncherCoordinator`, `AppActionsMenu` and `RootPaletteView` gate extension actions and accessories. `ExtensionCoordinator` rejects store-install links as well as its existing command-link gate. `AppCore` gates manager startup.
