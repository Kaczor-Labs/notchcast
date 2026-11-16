# Notchcast v2 island look audit

Audit of every surface Notchcast v2 draws on the island against `notchcast/docs/design-system.md` (spec at `fe9cf866a`, branch `v2/look-design-spec`). Branch `v2/look-audit`. No product code was changed; the only new Swift is the render harness `Tests/nc-Notchcast-island-audit-render-test.swift`.

## How to read this

- Items are numbered once, across the whole page, so a reply can say "fix 6, 8, 9".
- Each group is one fix unit (one small PR). Groups are ordered by their worst item; items inside a group by severity.
- Severity: **1** breaks the one-look rule at a glance or hides meaning (failure looks like success); **2** visible in a state (hover, pressed, selected, a dialog) or a whole class of surfaces; **3** token, literal or ink hygiene, invisible or nearly so.
- `Bn` = the spec's §14 known break n, folded in. "In flight" = being fixed on `v2/look-island-black` (worktree `look-black`, HEAD `5069ad8cf` on `579c5666e`, base `f776a9432`).
- `render NN` = PNG `NN-*.png` in `look-audit-renders/` beside this worktree (written with `NC_AUDIT_RENDERS` set to it), produced by the harness, all looked at.

### What `v2/look-island-black` actually covers

The brief marks B1–B4 as in flight. The look-black diff (read-only, checked at `5069ad8cf`, clean tree) covers less than that:

- **Covered:** B1 (footer capsule and menu circle). `frosted(in:)` now routes through `islandGlass`, which paints `islandSurface` and `.identity` glass when `paletteOnIsland` is true (`IslandPaletteSurface.swift`). This also blacks out every other `frosted(in:)` inside the island palette (Quick AI suggestion chips). B5's glass part is covered too: `UpdatePill.swift:90` now uses `islandGlass`. The compact launcher width and outline are also in flight (`579c5666e`).
- **Not covered:** B2 (`BarButton` selected fill), B3 (`MessageHUDView`) and B4 (`DialogView` scrim). Neither commit touches those files. HUD and dialog windows never see `paletteOnIsland`, so `islandGlass` cannot reach them either. They are listed below as open and need a unit of their own, or an explicit addition to look-black.
- **Footer press states:** the look-black commit message says the footer controls have no selected or pressed state, so none of them use `keyCapFill`. §9 asks for one (item 2).

## Findings by fix unit

### Unit A: footer (§9)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | `Tinycast/Palette/RootPaletteView.swift:1079`, `:1657` | §1, §9 footer capsule and menu circle: no glass (B1) | `frosted(in: Capsule())` and `frosted(in: Circle())` give a light glass rim and lift on the black (render 02) → island surface, no glass. **In flight on v2/look-island-black** (`5069ad8cf`). | footer |
| 2 | 2 | `Tinycast/Palette/RootPaletteView.swift:1639`–`:1660` (`MenuCircleButton`) | §9 menu circle: pressed `keyCapFill` | Hover `rowHover` only, no pressed state → `keyCapFill` on pointer-down. Not in look-black (its commit says no pressed state). | footer |
| 3 | 2 | `Tinycast/Palette/RootPaletteView.swift:1647`–`:1648` | §6, §9 menu circle glyph is an SF Symbol (B10, first half) | Two hand-drawn `Capsule()` bars, 14 and 8 × 1.5, spacing 3 → one SF Symbol at the menu-icon size, or the §15 `menuGlyphBars` token. Hook A7. | footer |
| 4 | 3 | `Tinycast/Palette/RootPaletteView.swift:1047` | §5 spacing from the scale, via metrics | `HStack(spacing: 2)` literal → `metrics.spacing.xxs` (or the token for 2). | footer |
| 5 | 3 | `Tinycast/Palette/RootPaletteView.swift:1003`–`:1005` (`pillTint`) | §6 Theme text inks | `.primary` → `Theme.Colors.textPrimary` (destructive branch already a token). | footer |

### Unit B: notices (§10, engine art)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 6 | 1 | `Tinycast/Features/Island/Service/IslandNoticeArt.swift` (no read of `isFailure`) | §10 a failure tints its glyph `Theme.Colors.destructive` (B8) | "Update failed" draws a white glyph, identical to any success notice (render 12 vs render 10) → glyph in `destructive`. Hook A12. | notices |
| 7 | 2 | `Tinycast/Features/Island/Model/IslandLiveState.swift:13`–`:14`, `Tinycast/Features/Island/Model/IslandPresentation.swift:19`, `Tinycast/Features/Notchcast/Downloads/Service/DownloadsModule.swift:46`, `:72`, `:79`, `:87`, `Tinycast/Features/Notchcast/Downloads/Service/DownloadsIslandBridge.swift:54` | §10 failure dwell 4 s via §15 `failureNotice`; normal dwell `Theme.Duration.messageHUD` | Failure notices stay 4 s (update), 5 s (two Downloads notices) or 2.4 s (three Downloads `isFailure` notices that keep the default). All dwells are literals → one failure dwell for every `isFailure` notice, from a token. | notices |
| 8 | 3 | `Tinycast/Features/Island/Service/IslandNoticeArt.swift:19`, `:33`–`:34` | §10 table, Installing: `arrow.down.circle` plus progress arc | A progress notice drops its glyph and draws the ring only (render 11) → either draw the glyph inside the arc, or change the spec (see spec issue S7). | notices |

Conforms: glyph and text `textPrimary` (render 10, `IslandCanvas.swift:104`–`:117`), progress track `Theme.Colors.border` (`IslandNoticeArt.swift:48`, render 11), status art (render 13), level art (render 14).

### Unit C: HUD and dialog (§10, §1)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 9 | 1 | `Tinycast/Windows/HUD/MessageHUDView.swift:59`, `:60`, `:79` | §1, §2, §10 HUD: island surface only, no glow, rim or scrim (B3) | Radial tinted glow, `panelScrim`, tinted `strokeBorder` rim; the neutral HUD shows a grey scrim and rim (render 05) → island surface, tone on the glyph only. Hooks A1, A2, A13. **Labelled in flight, but not in the look-black diff.** | HUD/dialog |
| 10 | 2 | `Tinycast/Windows/Dialog/DialogView.swift:62` | §1 dialog: island surface only (B4) | `.background(Theme.Colors.panelScrim, in: shape)` → island surface. On a black backdrop the scrim reads near-black, so renders 06/07 hide it; the rule break is from code. **Labelled in flight, but not in the look-black diff.** | HUD/dialog |
| 11 | 2 | `Tinycast/Windows/Dialog/DialogView.swift:15`–`:16`, `:121`–`:134` | §10 dialog icon = the subject's glyph at `metrics.size.dialogIcon`; tone on the glyph only | The symbol sits at `dialogSymbol` inside a tinted rounded tile (`tone.tint.opacity(0.12 / 0.18)`, `dialogSymbolContainer`); Update failed shows a red tile (render 06), a neutral dialog a grey tile (render 07) → bare glyph at `dialogIcon`. | HUD/dialog |
| 12 | 3 | `Tinycast/Windows/HUD/MessageHUDView.swift:52`, `:60` | §10 HUD hover `rowHover`; §6 Theme inks | Hover `controlHover`, text `Color.primary` → `rowHover`, `textPrimary`. Same PR as 9. | HUD/dialog |
| 13 | 3 | `Tinycast/Windows/HUD/VolumeHUDView.swift:39`, `:12` | §1 (B11) | `panelScrim` and `Color.primary` (hidden view, only the volume scene reaches it) → island surface, `textPrimary`. Not rendered. | HUD/dialog |
| 14 | 3 | `Tinycast/Windows/Dialog/DialogView.swift:21` | doc truth | Doc comment says "Tinycast's Liquid Glass dialog"; on the island it is not glass → fix the comment with item 10. | HUD/dialog |

### Unit D: buttons (§7)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 15 | 2 | `Tinycast/DesignSystem/BarButton.swift:64` | §7 selected `keyCapFill` on the island (B2) | `Theme.Colors.selection` (0.24) is clearly brighter than the `keyCapFill` target (0.14), render 03. **Labelled in flight, but not in the look-black diff.** Hook A9. | buttons |
| 16 | 2 | `Tinycast/DesignSystem/BarButton.swift:63`–`:66` | §7 pressed `keyCapFill`, shown on pointer-down | No pressed state at all (selected or hover only) → `keyCapFill` while pressed. | buttons |
| 17 | 2 | `Tinycast/DesignSystem/ModalActionButtonStyle.swift:43`–`:47` | §7 neutral button bare at rest, `rowHover`, `keyCapFill` (B6) | Cancel and Standard fill `controlSurface` at rest, `controlHover`, `controlPressed` (render 04, 06, 07). Role tints (Try Again, Delete) conform. Hook A9. | buttons |
| 18 | 2 | `Tinycast/Windows/Dialog/DialogChip.swift:12`–`:14` | §7 bare at rest, selected `keyCapFill` | Rest `controlSurface`, selected `selection` (render 08) → clear, `rowHover`, `keyCapFill`. | buttons |
| 19 | 3 | `Tinycast/DesignSystem/ModalActionButtonStyle.swift:31`, `Tinycast/DesignSystem/PopoverMenu.swift:431` | §15 "every value resolves to a token" | Disabled opacity `0.45` literal in two places → one token. | buttons |

### Unit E: update flow (§9, §10 state table)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 20 | 1 | `Tinycast/Features/Updates/UI/UpdatePill.swift:90`–`:91` | §1, §9 update pill: no glass (B5) | Tinted interactive `.glassEffect` → no glass. **Glass part in flight on v2/look-island-black** (`5069ad8cf` swaps it to `islandGlass`); the tint (`tintOpacity` 0.16) moves into `islandGlass`'s `Glass` argument and is dropped on the island. Not rendered (needs `UpdateCoordinator`). | update |
| 21 | 2 | `Tinycast/Features/Updates/UI/UpdatePill.swift:80`, `:104` | §9 the stage tint colours only glyph, ring and label; §7 bare at rest | The action capsule fills `tint.opacity(0.22)`; the close circle fills `controlSurface` → bare at rest, `rowHover` hover, `keyCapFill` pressed. Not in look-black. | update |
| 22 | 2 | `Tinycast/Features/Updates/UI/UpdatePill.swift:58`, `:64`, `:115` vs `Tinycast/Features/Island/Model/IslandLiveState.swift:25`–`:35` | §10 one glyph per state everywhere | Footer pill: `checkmark.circle.fill` (ready), `exclamationmark.circle.fill` (failed), `progress.indicator` (installing). Notice and status: `arrow.clockwise.circle`, `exclamationmark.arrow.circlepath`, `arrow.down.circle` → one glyph per state. | update |
| 23 | 2 | `Tinycast/Features/Updates/UI/UpdateCoordinator.swift:122` | §10 Try Again dialog shows the failed state's glyph (B9) | `arrow.down.circle` in a red tile (render 06) vs the notice's `exclamationmark.arrow.circlepath` → the same glyph. Hook A14. | update |
| 24 | 2 | `Tinycast/Features/Island/Service/IslandUpdateActivity.swift:70`–`:71` | §10 table, Ready: tap → relaunch | Tapping the ready notice or status opens the launcher (`showPalette(mode: .launcher)`); only the footer pill's "Relaunch" button relaunches → relaunch, or fix the spec (S8). | update |
| 25 | 3 | `Tinycast/Features/Updates/UI/UpdatePill.swift:20`–`:21`, `:120` | §10 progress track `Theme.Colors.border`; §15 tokens | Ring track is `tint.opacity(0.25)`; `tintOpacity` 0.16 and `actionOpacity` 0.22 are literals → `border` track, tokens or deleted with item 21. | update |

### Unit F: menu (§3, §8)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 26 | 2 | `Tinycast/DesignSystem/PopoverMenu.swift:129` | §3 menu panel radius 26, concentric with 18-pt rows (B7) | `metrics.radius.menuPanel` (16) → `NotchTheme.Radius.islandMenu` (26, §15, not yet defined). Hook A3. Not visible in render 09 (black on black); from code. | menu |
| 27 | 3 | `Tinycast/DesignSystem/PopoverMenu.swift:209`, `:321`, `:382`, `:389`, `:400`, `:407` | §6 Theme inks; destructive is `Theme.Colors.destructive` | `Color.red`, `.secondary`, `Color.secondary`, `Color.primary` → `destructive`, `textSecondary`, `textPrimary` (render 09 shows the red row). | menu |
| 28 | 3 | `Tinycast/DesignSystem/PopoverMenu.swift:193`–`:194` | §5 spacing scale (2·4·6·8·10·12·18·20·28) | `metrics.spacing.xxs / 2` = 1 pt, off the scale → a scale value. | menu |

Conforms: one `PopoverMenu` for the pill menu and every island menu, `menuHover` row, outline keycaps for shortcuts, search on top, header (render 09; `Tinycast/Features/Island/Service/IslandPillMenu.swift`). "Support Tinycast…" in the pill menu is the allowlisted upstream credit (`notchcast/docs/fork-strings.md`), not a finding.

### Unit G: tooltips (§13)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 29 | 2 | `Tinycast/DesignSystem/BarButton.swift:131`, `Tinycast/Palette/RootPaletteView.swift:906`, `:1680`, `Tinycast/Features/Launcher/UI/CompactBar.swift:106`, `Tinycast/Features/Launcher/UI/SectionHeader.swift:22`, `Tinycast/Features/Calculator/UI/CalculatorCardView.swift:97`, `Tinycast/Features/AI/UI/ChatTranscriptView.swift:174`, `:396`, `:414`, `Tinycast/Features/AI/UI/ChatSuggestionChips.swift:40` | §13.8 `.tooltip`, never `.help()`, in the palette | System `.help()` tooltips on island controls (the stock yellow tooltip over the black island) → `.tooltip`. `BarButton` and `HeaderBackButton` carry the most traffic. | tooltips |

### Unit H: launcher rows (§6, §8)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 30 | 3 | `Tinycast/Features/Launcher/UI/LauncherList.swift:319`–`:323` | §6 no hand-drawn glyphs (B10, second half) | 3 × 3 `Circle()` in `.secondary`, offset 3 → §15 `runningDot` token and `textSecondary`. Hook A7. | launcher |
| 31 | 3 | `Tinycast/Features/Launcher/UI/LauncherList.swift:341`–`:349` | §7 nothing neutral fills at rest | The alias chip fills `controlSurface` at `radius.menu` → spec has no chip rule (S12); either `keyCapFill` (a keycap-like chip) or bare. | launcher |

Conforms: compact launcher on the island (`CompactBar.swift`: `.identity` glass, no scrim, selected circle `keyCapFill`, glyphs through `SymbolImage`), expanded rows (`LauncherList.swift:296`–`:382`: selected `selection`, hover `rowHover`, outline keycaps, `radius.row`), stage widths and insets (`IslandController.swift:185`–`:210`, hook A4 = 0). Compact launcher width and outline: in flight (`579c5666e`).

### Unit I: ink, type and literal tokens (§5, §6)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 32 | 3 | `Tinycast/Features/Launcher/UI/LauncherList.swift:336`, `:342`, `:372`, `Tinycast/Features/Launcher/UI/SectionHeader.swift:27`, `Tinycast/Features/Launcher/UI/LeadCard.swift:62`, `Tinycast/Features/Launcher/UI/ColorCard.swift:21`, `Tinycast/Palette/EmptyResults.swift:11`, `:12`, `:16`, `Tinycast/Palette/RootPaletteView.swift:799` | §6 Theme text inks | SwiftUI `.secondary` / `.tertiary` hierarchical styles → `Theme.Colors.textSecondary` / `textTertiary`. On the pinned-Dark island the values are close; this is about one ink source. | tokens |
| 33 | 3 | `Tinycast/Features/Quicklinks/UI/QuicklinkListView.swift:119`, `Tinycast/Features/AI/UI/ChatComposerChips.swift:54` | §6 `metrics.typography` | `.font(.system(size: 10))` and `size: 9` → a typography token. ChatComposerChips: on the island only if the Quick AI screen shows it (Not verified). Emoji glyph sizes (`EmojiGridView.swift:320`, `:345`) are content, not chrome. | tokens |
| 34 | 3 | `Tinycast/Features/Clipboard/UI/ClipboardView.swift:304`, `:396`, `Tinycast/Features/Quicklinks/UI/QuicklinkListView.swift:155`, `Tinycast/Features/Snippets/UI/SnippetsListView.swift:143` | §5, §13.3 sizes via metrics | `.padding(.horizontal, 12)` × 3 and `.frame(width: 20, height: 20)` literals → metrics tokens. | tokens |
| 35 | 3 | `Tinycast/Features/Island/Service/IslandLevelArt.swift:10`–`:11`, `:22` | §15 a token per meaning | Level cell and track reuse `NotchTheme.Size.islandRest.height` / `.width`; correct today by coincidence, wrong the day the rest size changes → own tokens (spec S14). | tokens |

### Unit J: palette screens (cards, Quick AI)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 36 | 2 | `Tinycast/Features/AI/UI/ChatTranscriptView.swift:169`–`:170` | §1, §2 | "Jump to Latest" uses `.ultraThinMaterial` plus a `border` rim; it shows in the Quick AI screen on the island (`AIScreen.swift:179`) → bare `rowHover` circle. Hook A1 does not match `Material` (S2). | palette-screens |
| 37 | 2 | `Tinycast/Features/Clipboard/UI/ClipboardView.swift:337`, `Tinycast/Features/Clipboard/UI/ColorSwatch.swift:18`, `Tinycast/Features/Clipboard/UI/FilePreviewStage.swift:82`, `Tinycast/Features/Dictionary/UI/DictionaryEntryView.swift:95`, `Tinycast/Features/FileSearch/UI/FileSearchPreview.swift:54`, `Tinycast/Features/WindowManagement/UI/RoomPickerList.swift:120`, `Tinycast/Features/WindowManagement/UI/RoomPreviewView.swift:58`, `Tinycast/Features/AI/UI/MarkdownCodeView.swift:34`, `Tinycast/Features/AI/UI/MarkdownTableView.swift:46` | §2 no stroke on any island surface | Preview cards draw a `cardStroke` hairline. Hook A2 scope excludes palette screens, so these are uncounted. Decide in the spec first (S5): a card on black with no edge may need a fill instead. | palette-screens |
| 38 | 3 | `Tinycast/Features/Emoji/UI/EmojiGridView.swift:322`–`:333` | §2 | Selection ring and inner border strokes on the emoji grid → spec decision (S5); a selection ring may be a legitimate glyph. | palette-screens |
| 39 | 3 | `Tinycast/Features/AI/UI/AIEmptyState.swift:28` | §7 keycaps `.outline` | `KeyCapChip(text: "↵")` uses the filled style → `.outline`. In render 01 the two styles barely differ (S11). | palette-screens |
| 40 | 3 | `Tinycast/Features/AI/UI/ChatSuggestionChips.swift:55` | §1 no glass | `frosted(in: Capsule())`. In flight: look-black's `islandGlass` paints it black inside the island palette; in the stand-alone AI chat panel it keeps glass, which §0 allows. | palette-screens |

### Unit K: window chrome (§1, spec gap)

| # | Sev | Where | Rule | Today → rule | Area |
| --- | --- | --- | --- | --- | --- |
| 41 | 2 | `Tinycast/Palette/PalettePanel.swift:273`, `Tinycast/Palette/MenuPanel.swift:20`, `Tinycast/Windows/HUD/HUDPanel.swift:19`, `Tinycast/Windows/Dialog/DialogPanel.swift:39` | §1 "nothing under or over it" (spirit); spec silent on shadows (S4) | Every island window keeps `hasShadow = true`; the island overlay itself sets `hasShadow = false` (`IslandOverlayController.swift:21`, `:29`). A system window shadow under a black shape that should read as the notch. Not verified visually: shadows only show on a live screen. | surface |

## §0 coverage

| §0 surface | Verdict | Files | Items |
| --- | --- | --- | --- |
| Backdrop | conforms | `IslandBackdrop.swift:7` (clear window), `IslandCanvas.swift:18`–`:19` (fills `islandSurface`, no stroke) | 41 (window shadow, other panels only) |
| Launcher compact, empty and with results | conforms on this branch; width and outline in flight | `CompactBar.swift`, `LauncherList.swift` | 1, 29 (`CompactBar.swift:106`) |
| Launcher expanded | broken (footer, tooltips, inks) | `RootPaletteView.swift`, `LauncherList.swift` | 1–5, 15–16, 29–32 |
| Palette screens (Clipboard, Quick AI, Dictionary, File Search, Rooms, Emoji, Quicklinks, Snippets, Calculator) | broken (strokes, material, literals) | see unit J and I | 32–40 |
| Pill at rest, glance, status, level | conforms | `IslandCanvas.swift`, `IslandLevelArt.swift`, renders 13, 14 | 35 (token only) |
| Pill notice | broken | `IslandNoticeArt.swift`, renders 10–12 | 6–8 |
| Pill menu and every `PopoverMenu` from the island | broken (radius, inks) | `PopoverMenu.swift`, `IslandPillMenu.swift`, render 09 | 19, 26–28, 41 |
| Report HUDs | broken | `MessageHUDView.swift`, `VolumeHUDView.swift`, render 05 | 9, 12, 13, 41 |
| Dialogs | broken | `DialogView.swift`, `DialogChip.swift`, `ModalActionButtonStyle.swift`, renders 04, 06–08 | 10, 11, 14, 17–19, 41 |
| Update flow (UpdatePill, notice, Try Again) | broken | `UpdatePill.swift`, `IslandLiveState.swift`, `IslandUpdateActivity.swift`, `UpdateCoordinator.swift` | 6, 20–25 |
| Notchcast settings (§11) | conforms | `NotchcastSettingsView.swift` (grouped `Form`, `SettingsRowTitle`, `SettingsSectionHeader`; `Theme.Colors.warning` at `:67` is a status glyph, allowed) | none; hook A15 = 0 |
| Add-on surfaces (§12) | conforms | Music, Screenshots, Downloads, SmallCommands all post through `context.presenter`; only settings views and the exempt Screenshots overlay import SwiftUI | 7 (dwell), S3; hook A16 = 0 |

## §16 hooks

Run on `v2/look-audit` (`fe9cf866a`) with the spec's own commands. Counts match the recorded 6/1/1/0/0/0/3/0/4/0/2/1/5/1/0/0.

| Hook | Count | Hits → item |
| --- | --- | --- |
| A1 glass and scrim | 6 | `RootPaletteView.swift:1079`, `:1657` → 1; `VolumeHUDView.swift:39` → 13; `MessageHUDView.swift:60` → 9; `DialogView.swift:62` → 10; `UpdatePill.swift:91` → 20 |
| A2 stroke | 1 | `MessageHUDView.swift:79` → 9 |
| A3 menu radius | 1 | `PopoverMenu.swift:129` → 26 |
| A4 stage width | 0 | conforms |
| A5 padding literals | 0 | (palette screens outside hook scope → 34) |
| A6 font literals | 0 | (outside scope → 33) |
| A7 hand-drawn frames | 3 | `RootPaletteView.swift:1647`, `:1648` → 3; `LauncherList.swift:321` → 30 |
| A8 filled keycaps | 0 | (outside scope → 39) |
| A9 button fills | 4 | `BarButton.swift:64` → 15; `ModalActionButtonStyle.swift:43`, `:45`, `:47` → 17 |
| A10 menu widths | 0 | conforms |
| A11 footer glass | 2 | `RootPaletteView.swift:1079`, `:1657` → 1 |
| A12 failure glyph | 1 | `IslandNoticeArt.swift` never reads `isFailure` → 6 |
| A13 HUD and dialog | 5 | `VolumeHUDView.swift:39` → 13; `MessageHUDView.swift:59`, `:60`, `:79` → 9; `DialogView.swift:62` → 10 |
| A14 update glyph | 1 | `UpdateCoordinator.swift:122` → 23 |
| A15 settings form | 0 | conforms |
| A16 add-on windows | 0 | conforms |

The same hooks widened to every `Tinycast/Features/*/UI` folder and `.help(` / `.secondary` / `Color.red` patterns found items 27, 29, 32–40. Hits in `AIChatDetailView.swift`, `AIChatSidebarView.swift`, `AIChatWindowChrome.swift`, `CameraPreviewView.swift`, `AboutView.swift` and `ClipDrag.swift` are off the island (§0 lists the AI chat panel, Camera and other stock panels as out of scope; About is a stock window; `ClipDrag` draws a drag image), so they are not findings. `ChatMarkdownRenderer.swift:156`, `:424` use a 1-pt font as a spacer inside attributed text, not chrome.

## Spec issues

| # | Section | Issue |
| --- | --- | --- |
| S1 | §16 A6 | The font hook matches one line at a time, so a `.font(.system(size:` split over lines escapes it. |
| S2 | §16 A1 | The glass hook misses SwiftUI `Material` (`.ultraThinMaterial` etc.), which item 36 uses on the island. |
| S3 | §16 scope (`$I`) | The hooks cover `Palette/`, `Island/`, `Launcher/UI`, HUD, dialog and four design-system files, but §0 puts every palette screen on the island. Items 33, 34, 36–40 sit outside the hooks, so "every hook at or below its count" can pass while those break. |
| S4 | §1 | Window shadows are not covered. `hasShadow = true` on every island panel (item 41) is neither allowed nor forbidden. |
| S5 | §2 | "No stroke" vs separators, card hairlines and selection rings is ambiguous: `PopoverMenu`'s search separator, preview card strokes and the emoji selection ring are not named. A card on black with no edge and no fill disappears. |
| S6 | §10, §15 | `failureNotice` is proposed as `NotchTheme.Duration`, but `IslandLiveState` and add-on models live under `Model/`, which may not import SwiftUI and cannot read `Theme`/`NotchTheme`; the token must be a plain `TimeInterval` constant in a model-safe file. |
| S7 | §10 table | Installing "glyph plus progress arc" contradicts the art, which draws the ring alone (item 8). Decide which one is the target. |
| S8 | §10 table | Ready "tap: relaunch" contradicts the code, where the notice and status tap open the launcher and only the footer pill relaunches (item 24). A tap that relaunches straight from a passing notice may be too eager; decide. |
| S9 | §6 | "Glyphs through `SymbolImage`" is unenforceable by the hooks: `Image(systemName:)` is still used in `HeaderBackButton` (`RootPaletteView.swift:1662`–`:1682`), `PopoverMenu` and `ChatTranscriptView`. |
| S10 | §7 vs §8 | Two "selected" fills: launcher rows use `selection` (0.24), buttons `keyCapFill` (0.14). Render 03 shows the gap. If the goal is "one factory", pick one, or state why rows differ. |
| S11 | §7 | `.outline` keycaps have no outline: the style is a `keyCapFill` chip, and next to the filled style it looks almost the same (render 01). The name misleads builders; rename or define the difference. |
| S12 | §7 | Chips are not covered: the launcher alias chip (item 31), `DialogChip` (item 18) and Quick AI composer chips each fill differently. |
| S13 | §10 | `dialogIcon` (the rule) vs `dialogSymbol` (the code, 28 inside a 52 tile) are two different tokens; the spec should say whether `dialogSymbol` and `dialogSymbolContainer` are retired. |
| S14 | §15 | Level art (`IslandLevelArt`) sizes are not covered and reuse rest-pill sizes (item 35). |
| S15 | §10 table | The failed status glyph (`exclamationmark.arrow.circlepath` in the pill) has no stated colour; the notice gets `destructive`, the status does not say. |
| S16 | §10, §12 | Failure notices from add-ons use their own glyphs (`exclamationmark.triangle`, `folder`) and dwells (item 7). The spec states the update failure only; add one rule for every `isFailure` notice. |
| S17 | §0 | The Quick AI screen (`AIScreen`) is a palette screen, so on the island, but it shares `ChatTranscriptView`, `AIEmptyState` and `ChatSuggestionChips` with the out-of-scope AI chat panel. The spec should say whether the shared views follow the island rules everywhere or only under `paletteOnIsland`. |
| S18 | §13 | Text fields (the palette search field, `PopoverMenu` search) have no rule for fill, caret or placeholder ink. |

## Renders

Harness: `Tests/nc-Notchcast-island-audit-render-test.swift`, run by `./Scripts/run-tests.sh nc-Notchcast-island-audit-render-test`. Output folder: `NC_AUDIT_RENDERS`, else `$TMPDIR/nc-island-audit-renders`. SwiftUI surfaces render in Dark on `islandSurface`; engine art renders on a grey backdrop so the black pill shows.

| PNG | Shows | Items |
| --- | --- | --- |
| 01-keycaps | outline ⌘ K ↵ next to a filled ↵ | 39, S11 |
| 02-footer-capsule-today | frosted menu circle and footer capsule on black | 1 |
| 03-barbutton-states | rest, selected (`selection`), `keyCapFill` target | 15, S10 |
| 04-modal-buttons | Cancel, Standard, Try Again, Delete | 17 |
| 05-message-hud | success, danger, neutral, progress with cancel | 9, 12 |
| 06-dialog-update-failed | update-failed dialog | 10, 11, 23 |
| 07-dialog-neutral | neutral dialog with a destructive Quit | 11, 17 |
| 08-dialog-chips | rest and selected chips | 18 |
| 09-popover-menu | pill-style menu: search, header, highlighted row, keycaps, destructive row | 26, 27 |
| 10-notice-glyph | glyph notice "Copied" | conforms |
| 11-notice-installing | progress notice | 8 |
| 12-notice-failed | "Update failed" with `isFailure` | 6 |
| 13-status | ready status glyph | conforms |
| 14-level | volume level | conforms |

Not rendered offscreen, audited from code:

- `RootPaletteView`, `LauncherScreen`, `CompactBar`, `LauncherList` rows and every palette screen: they need `AppCore` plus the environment coordinators (`AliasStore`, `HotKeys`, `AppEntry`, screen sessions); stubbing them would mean a second app.
- `UpdatePill`: needs a live `UpdateCoordinator` stage.
- `VolumeHUDView`: hidden view, reached only by the volume scene; not attempted.
- Window shadows: drawn by the window server, visible only on a live screen, which the brief forbids.
- The dialog's `panelScrim` (item 10) and the menu's radius (item 26) are black on black in the renders; both are from code.
