# Notchcast island design system (v2)

Every surface Notchcast shows on the island is built from one factory: the tokens named here, the shared `DesignSystem/` components, and one rule per element. Tokens come from exactly two places: `NotchTheme` in `Tinycast/Features/Notchcast/NotchTheme.swift`, and `Theme`'s base tokens (spacing, radius, size, colour, typography) in `Tinycast/DesignSystem/Theme.swift`, read on scaled surfaces through `@Environment(\.metrics)` (`InterfaceMetrics`). A number or colour that is in neither is a missing token: it goes in §15, never into a view. Upstream's `docs/ui.md` (`abue-ammar/tinycast`) still governs every stock surface; where it and this page disagree about the island, this page wins.

Each section states one normative rule per element with its token, and one reference line. §14 lists where the code breaks a rule today; §16 is the check that finds each break.

## 0. Scope: what is on the island

| Surface | Window and level | Owner |
| --- | --- | --- |
| Backdrop (the island shape in its look, §1, and its edge) | `IslandBackdrop`, main menu + 1, never key | `IslandController` (engine) |
| Launcher, compact and expanded, and every palette screen | palette panel, + 2, `paletteOnIsland == true` | `RootPaletteView` |
| Pill at rest, glance, status, level, notice | engine art (`IslandCanvas`, `IslandNoticeArt`, `IslandHeadlineArt`, `IslandLevelArt`, `IslandExpansionArt`) | `IslandController` |
| Pill menu and every `PopoverMenu` opened from the island | `MenuPanel` | `IslandPillMenu`, `PaletteScreen` |
| Report HUDs | + 3 | `HUDPresenter`, `MessageHUDView` |
| Questions (dialogs) | + 4 | `DialogController`, `DialogView` |
| Update flow (pill, notice, Try Again) | footer, notice, dialog | `UpdatePill`, `IslandLiveState`, `UpdateCoordinator` |

Off the island and out of scope: the Settings window (stock, native macOS, §11), Notes, Camera, AI chat panels, Dictation and every other stock floating panel, which keep upstream's content → `panelScrim` → `GlassEffectView` recipe from `docs/ui.md`. `Features/Extensions/` is never touched. A view shared between a palette screen and an out-of-scope panel (`ChatTranscriptView`, `AIEmptyState`, `ChatSuggestionChips`) follows the island rules everywhere it is used; the panel's own `AIChat*` files keep upstream's recipe.

Reference: HIG Live Activities, "Live Activities in the Dynamic Island use a black opaque background."

## 1. Island surface

The island has two looks, chosen per display (`IslandLook`, island-shell.md "Look"): **Black**, the opaque black that blends with notch hardware, and **Frosted**, graphite glass. A display never set takes Black with a notch and Frosted without one. Both are dark; Light stays out.

| Element | Rule | Token |
| --- | --- | --- |
| The island shape, every form from rest to open (backdrop, launcher, palette screens) | Black: paint one opaque black surface. Frosted: one behind-window `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `.active`) in the backdrop window, masked to the engine outline every frame (`IslandFrost`), under the graphite tint the canvas fills the outline with. On a notch the glass hangs from the screen's top edge and the hardware is its black cutout. Under Reduce Transparency or Increase Contrast, Frosted drops the blur and paints solid. No second material on either look: no Liquid Glass (`frosted(in:)`, a non-`.identity` `.glassEffect`, `GlassEffectView`, a SwiftUI `Material`) and no `panelScrim` on the island. | Black `NotchTheme.Colors.islandSurface`; Frosted `islandGlassTint` (rgb 24 25 28 at 0.88), solid `islandGlassSolid` (#1c1d20) |
| Island controls over the shape (`islandGlass`, `frosted(in:)`) | Black: the control paints `islandSurface`. Frosted: no fill of its own, so the glass shows (`@Environment(\.islandFrosted)`), and a 1 pt control edge (§2). | as above |
| HUD and dialog panels, and the level band in the report slot | Black: one opaque black surface. Frosted: no fill (`islandPanelFill`), so the backdrop's glass, which grows over them, shows. | `NotchTheme.Colors.islandPanelFill` |
| AppKit-drawn ink (engine art, the level band, `FormTextInput`, `FormTextArea`, the AI transcript's text view) | `NSColor(token)` resolves no SwiftUI environment, so it is always Black's value. A representable resolves its tokens with `token.nsColor(in: context.environment)`; engine art takes `frosted` from its canvas's look (`token.islandInk(frosted:)`), so Frosted's inks and red reach AppKit too. | the §6 tokens |
| Menu panel (`PopoverMenu`) | Black: one opaque black surface. Frosted: `islandMenuBacking`, a behind-window `.hudWindow` blur masked to the menu shape under the denser menu tint, with the island's 1 pt edge; solid `islandGlassSolid` under Reduce Transparency or Increase Contrast. | Black `islandSurface`; Frosted `NotchTheme.Frosted.menuTint` (rgb 38 39 43 at 0.92), `islandEdge` |
| Window shadow | No `hasShadow` on any island window. Frosted lifts the shape with its own shadow in a click-through child window under the backdrop (`IslandLiftWindow`), drawn only once the spring settles and cut out under the glass: rest and live forms `NotchTheme.Shadow.islandLive` (0 6 18 −6, black 0.55), open forms (palette, question, report) `islandOpen` (0 30 70 −26, black 0.75). The bare notch at rest casts none. Black casts none. A Frosted menu panel takes the window shadow (`MenuPanelController`), Black's none. | `NotchTheme.Shadow` |

Every other island surface follows one of these rows on Frosted. Two never do and stay as they are: the extension panels (`ExtensionActionsPanel`, `ExtensionListPanel`: Liquid Glass, owned by `Features/Extensions/`, and Extensions are hidden) and upstream's volume box (`VolumeHUDView`, never constructed; the island's level replaces it).

The palette root keeps `.identity` glass on the island (`RootPaletteView`) and sets `islandFrosted` from the look of the display it opened on; the compact bar drops its capsule glass, button glass and scrim (`CompactBar`, `onIsland`). Hooks A1, A17.

Reference: HIG Materials, "Don't use Liquid Glass in the content layer."

## 2. Border and stroke

| Element | Rule | Token |
| --- | --- | --- |
| Any island surface or control | No stroke, rim, key line or `border` outline. A hairline inside art (a level zone, a progress track) is a glyph, not a border. One exception, the island's own edge, stroked inside the engine outline so the size never changes, mirrored over the palette content, and off with `islandOutlineWhenOpen` off. Black: one device pixel (`IslandKeyline.width`), white at 0.15, fading in with the outline's growth, 0 at rest, merging with the bezel and menu bar. Frosted: one point, white at 0.12, so the glass reads over a busy wallpaper; without a notch it stays full at rest too (`IslandKeyline.restingStrength`), so the rest pill keeps its edge; on a notch it runs down the sides and along the bottom (the top is above the screen) and is 0 at rest, where the outline is the hardware. Black has none in Light; Frosted's edge is the same in Light, because its glass stays graphite. A second exception, Frosted only: a neutral control (keycap, dialog button, footer capsule, menu circle) carries a 1 pt inside edge so it reads over the glass; on Black the token is clear. | none (`Theme.Size.hairline` only inside glyph art); Black `NotchTheme.Colors.islandKeyline`, Frosted `islandEdge`; control edge `NotchTheme.Colors.controlEdge` (Frosted white 0.14) |
| Separator (menu search, section break) | A `Theme.Size.hairline` rectangle filled, not stroked. | `NotchTheme.Colors.keyCapFill` |
| Rule inside a card (`MarkdownTableView`, the chat's table rows) | A `Theme.Size.hairline` rectangle filled, one step above the card's `keyCapFill` fill: the card's own colour vanishes where the rule is drawn over bare ground next to a filled header (the chat's rows). Stock keeps `cardStroke`. | `NotchTheme.Colors.cardRule`, the `selection` step (`.islandSeparator`) |
| Card edge (preview, code, table, swatch, note) | The card is a filled rounded rectangle with no edge; never `cardStroke` or a stroked rim. Stock keeps its `card` and `codeBlock` radii. An inline argument field (`InlineArgumentFields`) follows the same rule at rest: `.islandCardFill`, no edge; its focus accent and owed red edges stay, they are state, and stock keeps `cardStroke` (`ArgumentFieldEdgeStyle`). | `NotchTheme.Colors.keyCapFill` at `metrics.radius.row` (`.islandCardFill`, `.islandEdge()`, `radius.islandCard(onIsland:)`) |
| Selection mark (emoji cell, room card) | A fill, never a ring or inner border. | `Theme.Colors.selection` |

HIG draws a key line around the iPhone Dynamic Island in Dark Mode to separate it from content; on the Mac the Black island must read as part of the notch, so it gets none at rest, while Frosted glass needs its edge to read as an object. Hook A2.

Reference: HIG Live Activities, "When the background is dark — for example, in Dark Mode — a key line appears around the Dynamic Island to distinguish it from other content."

## 3. Radius

| Element | Rule | Token |
| --- | --- | --- |
| Island outline | Fixed at every interface scale (1, 1.1, 1.2). | `Theme.Radius.panel` (26) |
| Any shape inside an island surface | Concentric: inner radius = outer radius − the inset between them, read from `metrics.radius`. Launcher rows `metrics.radius.row` (18), menu rows `metrics.radius.menuRow` (18), keycaps `metrics.radius.keyCap` (10), dialog `metrics.radius.panel`, buttons and HUDs `Capsule()`. A menu panel is menu row + list inset = 26. | `metrics.radius.*`; menu panel → `NotchTheme.Radius.islandMenu` (§15) |

Today `PopoverMenu` uses `metrics.radius.menuPanel` (16), smaller than the 18-point rows it holds. Hook A3.

Reference: HIG Live Activities, "Use consistent margins and concentric placement."

## 4. Widths

| Element | Rule | Token |
| --- | --- | --- |
| Launcher, every state (compact empty, compact with results, expanded) | One width; the island's stage width follows the palette frame and never shrinks to the capsule. Height: `metrics.size.compactHeight` (56) compact, `metrics.size.panelHeight` (475) expanded. | `metrics.size.panelWidth` (750) |
| Pill at rest | The sensor's size on a notched screen; otherwise the rest size, hung from the screen's top edge (default) or, by `appearance.islandPosition`, centred in or flush with the bottom of the menu bar (3 or 6 pt down on a 30 pt bar). Every island surface opens from that pill's top. | `NotchTheme.Size.islandRest` (96 × 24) |
| Glance, status, compact notice | The rest pill plus at most one wing per side. | `NotchTheme.Size.islandGlanceWing` (140) |
| Level art | Its own cell and track, never the rest pill's size; one continuous fill from the bar's left edge, outlined zones included, its width the readout's percent of the bar (brightness: darkest 0% empty, system minimum 20% a fifth, 100% full; volume 0…1 fills the track as before), with no extra marker; the track ends in the value as a whole percent (`IslandLevel.readout`, half away from zero, over the whole bar including the outlined zones, so the darkest extra dimming reads 0%, the system minimum 20% and nothing reads below 0% or above 100%; VoiceOver and the brightness Settings row read the same number), right-aligned in the stock volume HUD's readout width, island glance font, secondary text colour. | `NotchTheme.Size.islandLevelCell`, `islandLevelTrack` (§15), `Theme.Size.volumeReadout`, `NotchTheme.Typography.islandGlanceNSFont`, `Theme.Colors.textSecondary` |
| Menus | A fixed width token per menu; the pill menu and ⌘K use the action width. | `metrics.size.actionMenuWidth` (320), `menuWidth`, `clipboardFilterMenuWidth`, `fileSearchFilterMenuWidth`, `emojiCategoryMenuWidth` |
| HUD | Hugs its text up to the cap. | `metrics.size.hudMaxWidth` (420) |
| Dialog | Two sizes only. | `metrics.size.dialogWidth` (420), `metrics.size.dialogCompactWidth` (290) |

The engine's host canvas is `NotchTheme.Size.islandHost` (1100 × 860), which fits the 900-point scale-1.2 palette. Hook A4.

Reference: HIG Live Activities, "Maintain the relative placement of elements to create a coherent layout between presentations."

## 5. Padding

| Element | Rule | Token |
| --- | --- | --- |
| All island content | Insets come from the spacing scale only (2 · 4 · 6 · 8 · 10 · 12 · 18 · 20 · 28): header `metrics.size.headerPadding` (10), list and menu inset `metrics.spacing.md` (8), HUD `metrics.spacing.xl` × `metrics.spacing.lg`, dialog `metrics.spacing.dialogInset` (18), overlays `NotchTheme.Spacing.islandInset` (16) from the island edge with `Theme.Spacing.xl` (12) between them. | `metrics.spacing.*`, `NotchTheme.Spacing.islandInset` |

Hook A5.

Reference: HIG Live Activities, "Keep content compact and snug within a margin that's concentric to the outer edge of the Live Activity."

## 6. Type and icon

| Element | Rule | Token |
| --- | --- | --- |
| Type | Text styles only, through `metrics.typography`; no `.font(.system(` call at all, however its arguments are split over lines (`rowTitle`, `rowTrailing`, `bar`, `menuRow`, `menuShortcut`, `sectionHeader`, `panelTitle`, `searchField`); AppKit art uses its one font. Ink is `Theme.Colors.textPrimary` / `textSecondary` / `textTertiary` in their Dark branch, guaranteed because the app's appearance is pinned to Dark (`NotchcastIslandPins.appearance`). On Frosted the same tokens resolve `NotchTheme.Frosted` (#f2f3f5, #b6b8c1, #adb0b9; status red #ff827a, green #86d39b, yellow #e8c66a), each at 4.5:1 or better on the glass over a white wallpaper; on a slab (a selected row through `selectionFrame`, a highlighted menu row, a focused argument field, a dialog button label: `\.islandInkLifted`) secondary and tertiary lift to primary and red to #ffb3ae. Text that used SwiftUI's `.secondary` takes `NotchTheme.Colors.secondaryLabel`, which keeps that grey on Black and is `textSecondary` on Frosted; `Color.red` is `Theme.Colors.destructive`. | `metrics.typography.*`, `NotchTheme.Typography.islandGlanceNSFont` |
| Icon | Every glyph through `SymbolImage`, never a bare `Image(systemName:)`, at a slot token, monochrome in the text ink: result rows `metrics.size.resultRowIcon` (28), header `metrics.size.headerIconSlot` (22), menus `metrics.size.menuIcon` (20) in `Theme.Colors.menuSymbol`. Colour on a glyph only for status (§10). Never a hand-drawn glyph. | `metrics.size.*Icon*`, `Theme.Colors.menuSymbol` |

Hooks A6 (type), A7 (icon frames), A18 (`Image(systemName:)`).

Reference: HIG Live Activities, "Ensure unified information and design of the compact presentations… use consistent color and typography."

## 7. Keycap and button

| Element | Rule | Token |
| --- | --- | --- |
| Keycap | `KeyCapChip(style: .outline)` everywhere on the island (the style is a `keyCapFill` chip with no outline, §2; `.filled`, a `controlSurface` chip, is never used on the island), sized `.standard` (`metrics.size.keyCap`, 22) or `.compact` (`metrics.size.compactKeyCap`, 15); ink `keyCapInk` (Black `textSecondary`, Frosted #e4e6ea); on Frosted the fill is white 0.07 with the control edge. | `NotchTheme.Colors.keyCapFill`, `keyCapInk`, `metrics.radius.keyCap` |
| Button (`BarButton`, dialog buttons, compact circles) | At rest no fill, so the island shows through; hover `Theme.Colors.rowHover`; selected or pressed `NotchTheme.Colors.keyCapFill`, shown on pointer-down. Height `metrics.size.barButtonHeight` (28) in bars, `metrics.size.dialogButtonHeight` in dialogs. A role button (`.modalAction(.primary)`, `.destructive`) keeps its role tint, `Theme.Colors.primaryAction` or `Theme.Colors.destructive`, because there the colour carries meaning. Frosted: a neutral dialog button takes the control edge; the primary is the one accent, solid #f2f3f5 with #111214 ink (`IslandButtonFill.primary`); the destructive wash is half Black's under the lifted red (`IslandButtonFill.destructive`). | `Theme.Colors.rowHover`, `NotchTheme.Colors.keyCapFill` |
| Chip (alias, attachment, suggestion, `DialogChip`) | One chip fill. A label chip (launcher alias, composer attachment) is a keycap-shaped `keyCapFill` chip; a selectable chip (`DialogChip`, suggestion) is a button: bare at rest, `rowHover`, selected `keyCapFill`. No `controlSurface` or `frosted` chip. | `NotchTheme.Colors.keyCapFill`, `metrics.radius.keyCap` |
| Text field (palette search field, `PopoverMenu` search) | No fill and no box: the island shows through, set off by the §2 separator. Typed text `textPrimary`, placeholder `textTertiary`, caret `textPrimary`, through `metrics.typography.searchField`. | `Theme.Colors.textPrimary`, `Theme.Colors.textTertiary` |

Two selected fills, on purpose: a launcher row is the list's one cursor and must read at a glance on a large black area, so it takes `selection` (0.24, §8); a button's selected or pressed state is a small control beside labelled neighbours and must stay quieter, so it takes `keyCapFill` (0.14). Never swap them.

The trade-off: a neutral control at rest is black on black, so its label alone carries the affordance. Keep every neutral control labelled with text or a glyph and never icon-only without a tooltip. Hooks A8 (keycap), A9 (button).

Reference: mac-design, "Hover and press never lower contrast"; apple-design, "Highlight a button the instant it's pressed."

## 8. Menu

| Element | Rule | Token |
| --- | --- | --- |
| Every menu on the island (pill menu, ⌘K actions, header filters) | One `PopoverMenu` in its own `MenuPanel` on the island surface, at a §4 width token, list inset `metrics.spacing.md`, rows `metrics.size.menuRowHeight` at `metrics.radius.menuRow`, highlighted row `Theme.Colors.menuHover`, shortcuts as outline keycaps, empty state "No Results" in `textTertiary`. The pill menu is the same component: header `Bundle.main.appDisplayName`, `Theme.Size.pillMenuVisibleRows` (13) rows, search at the top, anchored below the pill. Never `.contextMenu`, `NSMenu`, `NSAlert` or a system popover. | `NotchTheme.Colors.islandSurface` (Frosted: §1 menu panel), `Theme.Colors.menuHover` (Frosted white 0.10), `metrics.size.actionMenuWidth` |

A launcher result row follows the same grammar: selected `Theme.Colors.selection`, hover `Theme.Colors.rowHover`, else clear. On Frosted selection is white 0.12 and hover 0.06, so the slab never costs its row's text its contrast. Hook A10.

Reference: HIG Live Activities, "When separating a block of content, place it in an inset container shape… Don't draw content all the way to the edge."

## 9. Footer controls

| Element | Rule | Token |
| --- | --- | --- |
| Footer capsule (the action group: primary action, ⌘↵, Actions ⌘K) | `BarButton`s in a `Capsule()` padded `metrics.spacing.xs`, drawn on the island surface with no glass and no fill; each button follows §7. Bar height `metrics.size.bottomBarHeight` (44). | `NotchTheme.Colors.islandSurface`, `NotchTheme.Colors.keyCapFill` |
| Menu circle (hidden, #882: the footer shows no left button; rules kept for upstream sync) | A `Circle()` of `metrics.size.menuButton` (36), no glass and no fill at rest, hover `Theme.Colors.rowHover`, pressed `NotchTheme.Colors.keyCapFill`; its glyph is an SF Symbol (§6). | `metrics.size.menuButton` |
| Update pill in the footer | Same shape as the footer capsule (`metrics.size.menuButton` tall), no glass; the stage tint (`Theme.Colors.progress`, `success`, `destructive`) colours only its glyph, ring and label. | `Theme.Colors.progress`, `Theme.Colors.success`, `Theme.Colors.destructive` |

Hook A11 (plus A1 for the update pill).

Reference: HIG Materials, "Use Liquid Glass effects sparingly."

## 10. Notices, HUDs and dialogs

| Element | Rule | Token |
| --- | --- | --- |
| Notice (engine art) | Without a notch: one glyph and one short text in the pill's wings (§4). On a notch a notice with text grows the island below the notch, like the meeting expansion: glyph and text on one centred line, as wide as the text needs up to 320 pt (`NotchTheme.Size.islandHeadlineMaxWidth`), a longer text truncating at its tail with an ellipsis, and never narrower than the notch plus two `Theme.Radius.panel`; the line fades in over the outer half of the grow and is gone by the middle of the contract. Glyph and text `textPrimary`, progress as a `textPrimary` arc on a `Theme.Colors.border` track; an unknown fraction shows the glyph alone, never a ring. Dwell `Theme.Duration.messageHUD` (2.4 s). Tap opens the follow-up. | `NotchTheme.Typography.islandGlanceNSFont`, `NotchTheme.Size.islandHeadlineMaxWidth` |
| Failure (every `isFailure` notice, from the update flow or an add-on) | Glyph `Theme.Colors.destructive` in the notice, the status and the footer; text stays `textPrimary`. Dwell `IslandNotice.failureSeconds` (4 s), which `IslandNotice.dwell` applies whenever `isFailure` is set and `seconds` is left unset; a failure poster leaves `seconds` unset. The glyph shape is the poster's, its colour and dwell are not. | `IslandNoticeArt.failureTone` (`Theme.Colors.destructive`), `IslandNotice.failureSeconds` |
| HUD and dialog shown in the island | The island surface alone: no glow, no rim, no scrim. HUD: `Capsule()`, `metrics.typography.bar`, hover `Theme.Colors.rowHover`, tone on its glyph only. Dialog: `RoundedRectangle(cornerRadius: metrics.radius.panel)`, padding `metrics.spacing.dialogInset`, icon = the subject's bare glyph at `metrics.size.dialogIcon`, with no tinted tile (`dialogSymbol` and `dialogSymbolContainer` are retired), buttons `.modalAction(role)` per §7, ↵ primary, Esc cancel. | `NotchTheme.Colors.islandSurface` |
| Result | Any island activity that shows progress ends with a result notice, never just a vanish: success is a checkmark glyph and a short title, failure is the failure rule above (red glyph, 4 s). | `textPrimary`, `Theme.Colors.destructive` |
| Notch layout | On a notched display, the compact form beside the notch is a glyph and a short status only: progress is the ring left of the notch and the bare percent right of it, rounded down so it never claims 100 % early. Any text (a title, a message) expands out of the notch and shows below it, as the Dynamic Island expanded form. Titled progress (a download with its title) expands for one message dwell, then stays compact until it is ended, whatever its text; untitled progress (the update installing) is compact from the start; the result notice expands again. On a non-notched display the pill keeps its centred text. | `IslandNotice.messageSeconds` (2.4 s), sizes in §15 |

The update flow is one state machine shown in three places, with one glyph per state everywhere, except Installing, which shows its progress ring instead while the fraction is known:

| State | Notice | Pill status | Footer pill | Tap |
| --- | --- | --- | --- | --- |
| Installing | compact: progress ring and percent, or the `arrow.down.circle` glyph alone while the fraction is unknown | none | progress ring, `Theme.Colors.progress` | none |
| Ready | "Update ready", 2.4 s | `arrow.clockwise.circle` | `Theme.Colors.success` | notice and status open the launcher; only the footer pill's Relaunch relaunches |
| Failed | "Update failed", 4 s, glyph `destructive` | `exclamationmark.arrow.circlepath`, glyph `destructive` | `Theme.Colors.destructive` | `UpdateCoordinator.showFailure` → dialog "Update failed" with the same glyph and "Try Again" as `.modalAction(.primary)` |

Hooks A12 (notice), A13 (HUD and dialog), A14 (update glyph).

Reference: mac-design, "Status color always comes with an icon or a word."

## 11. Settings rows

| Element | Rule | Token |
| --- | --- | --- |
| Every Notchcast settings row | Stock, native macOS in the stock Settings window: one grouped `Form` (`.formStyle(.grouped)`) in `NotchcastSettingsView`, rows as native `Toggle` / `Picker` with `SettingsRowTitle` plus a one-line subtitle, `SettingsSectionHeader` per add-on. No island token and no custom fill. | none; upstream `SettingsComponents` |

Hook A15.

Reference: mac-design, "Use the system first. Add custom design only where the system has nothing."

## 12. Add-on surfaces

| Element | Rule | Token |
| --- | --- | --- |
| Anything an add-on shows | Only the island's values, posted through `context.presenter` (`IslandPresenting`: `showLevel`, `post(_:onTap:)`, `end(notice:)`, `setStatus`, `setMenuRows`) as `IslandLevel`, `IslandNotice`, `IslandStatus` (text cut to 4 characters) and `IslandMenuRow`, and `setPage` for its page in the open island (§17) as an `IslandPage`; the engine draws them with §1–§10 and §17. A failure it posts (`isFailure`) follows the §10 failure rule. An add-on opens no window, panel or hosting view of its own. Exempt: the Screenshots selection overlay, a capture tool over the whole screen, not an island surface. | none; `IslandPresenting` |

Hook A16.

Reference: HIG Live Activities, "Focus on simple, direct actions."

## 13. Builder checklist

1. Name the surface in §0; if it is not on the island, follow `docs/ui.md` instead of this page.
2. Paint nothing of your own behind content (§1, §2): the backdrop paints the look, no Liquid Glass on the island, and island controls go through `islandGlass` so they are `islandSurface` on Black and bare on Frosted.
3. Read the look of the display the surface opens on, in its host (`islandFrosted` from the palette, `MenuPanelController`, `IslandCoordinator.frosted(on:)`, or the canvas's `look`), and render it in Black and Frosted, in both forms (the Dynamic Island on a display without a notch, and the notch form), before READY. No `islandSurface` fill outside a look branch and no `NSColor(token)` ink: `nc-Notchcast-frosted-guard-test` fails on both.
4. Read every size from `@Environment(\.metrics)`; every new number goes to §15 first.
5. Radius concentric to the parent (§3); width from a §4 token; padding from §5.
6. Type and ink from §6; glyphs through `SymbolImage`; colour only for status.
7. Keycaps `.outline`; buttons bare at rest, `rowHover`, `keyCapFill` on press (§7).
8. Menus through `PopoverMenu` (§8), with no glass on the menu, its search field or its rows; questions through `DialogController`; reports through `HUDPresenter` or an `IslandNotice` (§10).
9. Every custom control has an accessibility label and traits; movement returns `nil` under Reduce Motion; `.tooltip`, never `.help()`, in the palette (a view shared with a stock surface calls `.paletteHelp`, which is `.tooltip` on the island and `.help` elsewhere).
10. Copy: Title Case for commands, buttons, menu items and outcomes, as stock macOS does ("Grant Access…"); sentence case for settings rows and other text; English only (`fork-strings.md`). `notchcast/design-check.sh` enforces the same split; an editor title in Title Case, like upstream's "Add MCP Server", takes an `ai-design-check-ignore-next-line sentence-case` line.
11. Dark only: the island is pinned Dark; check Dark, never Light.
12. Every progress activity ends with a result notice, success or failure (§10).
13. Beside the notch show a glyph and a short status only; text expands below the notch on notched displays, and stays centred in the pill elsewhere (§10).
14. Run §16 before READY: every hook at or below its recorded count.

## 14. Breaks today

The island-black branch is fixing the first four, and #8 is closed; the rest are open. Counts are from §16.

| # | Where | Breaks | Target |
| --- | --- | --- | --- |
| 1 | `RootPaletteView.swift:1079`, `:1657` | §1, §9: footer capsule and menu circle use `frosted(in:)` | no glass, §9 |
| 2 | `BarButton.swift:64` | §7: selected fill is `Theme.Colors.selection` | `NotchTheme.Colors.keyCapFill` on the island |
| 3 | `MessageHUDView.swift:59`, `:60`, `:79` | §10: radial glow, `panelScrim` and a tinted `strokeBorder` rim | island surface only |
| 4 | `DialogView.swift:62` | §1: `panelScrim` under the island surface | island surface only |
| 5 | `UpdatePill.swift:90` | §1, §9: tinted interactive `.glassEffect` | no glass, tint on glyph and label |
| 6 | `ModalActionButtonStyle.swift:43`–`:47` | §7: neutral buttons fill `controlSurface` / `controlHover` / `controlPressed` | bare, `rowHover`, `keyCapFill` on the island |
| 7 | `PopoverMenu.swift:129` | §3: menu radius 16 inside 18-point rows | `NotchTheme.Radius.islandMenu` |
| 8 | `IslandNoticeArt.swift` | Closed: the failure glyph is `IslandNoticeArt.failureTone` and its dwell `IslandNotice.failureSeconds` (#732); on a notch the notice text expands below (§10) | done |
| 9 | `UpdateCoordinator.swift:122` | §10: Try Again dialog shows `arrow.down.circle`, the notice `exclamationmark.arrow.circlepath` | one glyph per state |
| 10 | `RootPaletteView.swift:1647`–`:1648`, `LauncherList.swift:321` | §6: hand-drawn menu-circle bars (14 and 8 × 1.5) and a 3 × 3 running dot | SF Symbol, or §15 tokens |
| 11 | `VolumeHUDView.swift:39` | §1: `panelScrim` (hidden view, reached only by the volume scene) | island surface only |
| 12 | `PalettePanel.swift:273`, `MenuPanel.swift:20`, `HUDPanel.swift:19`, `DialogPanel.swift:39` | §1: `hasShadow = true` | `false` |
| 13 | `ChatTranscriptView.swift:169`–`:170`, `ChatSuggestionChips.swift:55` | §1, §2: `.ultraThinMaterial` with a `border` rim, a `frosted` chip | `rowHover` circle, §7 chip |
| 14 | palette-screen cards, `EmojiGridView.swift:322`–`:333` | §2: `cardStroke` hairlines and a selection ring | fill, §2 |

## 15. Tokens to add

| Proposed token | Value | For | Why |
| --- | --- | --- | --- |
| `NotchTheme.Radius.islandMenu` | 26 (`Theme.Radius.menuRow` 18 + `Theme.Spacing.md` 8) | §3 menu panel on the island | concentric with its rows; equals the island outline |
| `NotchTheme.Size.menuGlyphBars` | 14 and 8 wide, 1.5 thick | §9 menu circle | only if the hand-drawn bars stay; an SF Symbol needs no token |
| `NotchTheme.Size.runningDot` | 3 | §6 running-app dot in launcher rows | today a literal in `LauncherList` |
| `NotchTheme.Size.islandLevelCell`, `islandLevelTrack` | 24 and 96 | §4 level art | defined (#756): `IslandLevelArt` reads them instead of the rest pill's height and width |
| `Theme.Typography.indicatorGlyphSize` → `metrics.typography.indicatorGlyph` | 10 | §6 Quicklinks list indicator glyph (`QuicklinkListView`) | defined (#756) |
| `Theme.Typography.removeGlyphSize` → `metrics.typography.removeGlyph` | 9, semibold | §6 composer chip remove glyph (`ChatComposerChips`) | defined (#756) |
| `NotchTheme.Size.islandArtwork` | 64 (2 × `Theme.Size.resultRowIcon`) | §17 the Player page's cover | defined (#975): no media size existed; a row icon is too small to read a cover |

The notch expanded form needs one token, `NotchTheme.Size.islandHeadlineMaxWidth` (320): its height is the rest outline plus one headline line, its width the text up to that cap, never narrower than the notch plus two `Theme.Radius.panel` (§10).

The failure dwell is not a token: `IslandNotice.failureSeconds` (beside `messageSeconds`, 2.4 s) is a plain `TimeInterval` in `Features/Island/Model/`, which cannot import `NotchTheme`; `IslandLiveState.failureSeconds` is its alias (§10).

Nothing else is missing: every other value on the island resolves to a token named above.

## 16. Audit hooks

Run from the repo root with `bash`, after ``I=$(find Tinycast/Palette Tinycast/Features/Island Tinycast/Features/{AI,Calculator,Clipboard,Dictionary,Emoji,FileSearch,Launcher,Quicklinks,Snippets,Updates,WindowManagement}/UI Tinycast/Windows/HUD Tinycast/Windows/Dialog Tinycast/DesignSystem/{PopoverMenu,BarButton,KeyCapChip,ModalActionButtonStyle}.swift -name '*.swift' | grep -vE '/AIChat[A-Za-z]*\.swift$')`` (every on-island palette screen, §0; not the stock panels). Each prints one line per violation; "Hits" is the count at the commit that wrote this page, so a hook may only go down.

| Hook | Rule | Check | Hits |
| --- | --- | --- | --- |
| A1 | §1 surface | `grep -rnE -A1 'frosted\(in:\|\.glassEffect\(\|GlassEffectView\(\|panelScrim\|Material' $I \| grep -E 'frosted\(in:\|\.regular\|GlassEffectView\(\|panelScrim\|Material' \| grep -vE 'onIsland \? \.identity\|IslandVerification\.stock\|CompactBar\.swift[:-]123'` | 8 |
| A2 | §2 stroke | `grep -rnE 'strokeBorder\|\.border\(\|cardStroke\|emojiSelectionBorder\|emojiInnerBorder\|roomCardStroke' $I \| grep -v 'controlEdge'` (Frosted's control edge, §2) | 20 |
| A3 | §3 radius | `grep -rnE 'radius: metrics\.radius\.menuPanel' $I` | 1 |
| A4 | §4 widths | `grep -rnE 'stageWidth: [^s]' Tinycast/Features/Island/Service/IslandController.swift \| grep -vE 'panelWidth\|size\.width\|stageWidth: width'` | 0 |
| A5 | §5 padding | `grep -rnE '\.padding\((\.[a-zA-Z]+, )?[0-9]\|spacing: [0-9]{2,}' $I` | 3 |
| A6 | §6 type | `grep -rnE 'font\(\.system\(\|^\s*\.system\(size\|NSFont\.systemFont\(ofSize: [0-9]' $I` | 15 |
| A7 | §6 icon | `grep -rnE 'frame\(width: [0-9]+(\.[0-9])?, height: [0-9]' $I` | 4 |
| A8 | §7 keycap | `grep -rn 'KeyCapChip(' $I \| grep -v 'style: .outline'` | 1 |
| A9 | §7 button | `grep -rnE 'Theme\.Colors\.(selection\|controlSurface\|controlHover\|controlPressed)' Tinycast/DesignSystem/BarButton.swift Tinycast/DesignSystem/ModalActionButtonStyle.swift` | 4 |
| A10 | §8 menu | `grep -rnE -A3 '(headerMenu\|PopoverMenu)\(' Tinycast --include='*.swift' \| grep -E 'width: [0-9]'` | 0 |
| A11 | §9 footer | `grep -rnE 'frosted\(in: (Capsule\|Circle)\(\)\)' Tinycast/Palette/RootPaletteView.swift` | 2 |
| A12 | §10 notice | `grep -q 'failureTone' Tinycast/Features/Island/Service/IslandNoticeArt.swift \|\| echo 'IslandNoticeArt.swift: no failure tone'` | 0 |
| A13 | §10 HUD and dialog | `grep -rnE '\{ glow \}\|strokeBorder\|panelScrim' Tinycast/Windows/HUD Tinycast/Windows/Dialog` | 5 |
| A14 | §10 update glyph | `grep -rn 'symbol: "arrow.down.circle", recovery' Tinycast/Features/Updates/UI/UpdateCoordinator.swift` | 1 |
| A15 | §11 settings | `grep -rnE 'formStyle\(\|NotchTheme\.' $(grep -rlE 'struct [A-Za-z]+SettingsView' Tinycast/Features/Notchcast) \| grep -v 'formStyle(.grouped)'` | 0 |
| A16 | §12 add-ons | `grep -rnE ': NSPanel\|NSHostingView\(\|NSWindow\(' Tinycast/Features/Notchcast --include='*.swift' \| grep -v '/Screenshots/'` | 0 |
| A17 | §1 shadow | `grep -rnE 'hasShadow = true' Tinycast/Palette/PalettePanel.swift Tinycast/Palette/MenuPanel.swift Tinycast/Windows/HUD/HUDPanel.swift Tinycast/Windows/Dialog/DialogPanel.swift Tinycast/Features/Island` (window shadows stay off; Frosted's lift is a layer shadow in `IslandFrost`) | 4 |
| A18 | §6 glyph | `grep -rnE 'Image\(systemName' $I` | 39 |
| A19 | §1 look on Frosted | `./Scripts/run-tests.sh nc-Notchcast-frosted-guard-test \| grep -c '^FAIL'` (an `islandSurface` fill outside a look branch, an `NSColor(token)` ink) | 0 |

In the table `\|` is a Markdown escape: type a plain `|`.

## 17. Island pages

The open island (hover, or a click that pins it) shows pages: one per add-on with data, posted through `IslandPresenting.setPage` as an `IslandPage` and drawn by the core in `Features/Island/UI/` (decisions 946-1, 946-2, 946-6, 946-12). An add-on describes the page; it never draws one (§12).

| Element | Rule | Token |
| --- | --- | --- |
| Structure | A tab bar, then the page body. One page with data: no Home and no tab bar, hover opens that page. Two or more: Home first, then pages by `order` (Agents 0, Player 10, System 20, Day 30). A page with no data posts nil and leaves no tab. | `IslandPageDeck` |
| Tab | `BarButton(isSelected:)` with a `SymbolImage` and the title; the selected tab uses the button's selected fill. | `metrics.typography.bar`, `Theme.Typography.menuSymbolSize` |
| Badge | A count of things waiting for the user, a compact outline keycap after the tab title; badged pages lead Home, tabs never reorder. | `KeyCapChip(.outline, .compact)` |
| Home line | One row per page: icon or artwork, text, detail, its own icon buttons; the row opens its page. | `metrics.size.resultRowIcon`, `rowTitle`, `rowTrailing`, `Theme.Colors.rowHover` at `metrics.radius.row` |
| Blocks | `media` (cover, title, artist, time bar, transport), `row` (icon, title, detail, trailing; a button when it has an id), `meter` (label, bar, value). A new kind of content is a new block, drawn once here. | `NotchTheme.Size.islandArtwork`, `metrics.size.volumeTrackHeight`, `Theme.Colors.border` track |
| Icon button | `BarButton(isCompact: true)` with a `SymbolImage`, an accessibility label and `.tooltip`, Title Case ("Next Track"). | §7 |
| Size | Each page sizes to its content (`fittingSize`), padded `metrics.spacing.md`; never narrower than the rest pill, on a notch never narrower than the notch plus two `Theme.Radius.panel`, never taller than the screen; text lines stop at `islandHeadlineMaxWidth`. | `IslandPageDeck.outline` |
| Motion | The outline grows to the page through the engine's spring (`surface.expand`, `contentKey` "page"), as the launcher does; no view animation of its own. | `IslandController.motionSpeed` |
| Forms | Same page in both forms: it hangs from the island top, below the notch on a notched display, from the pill elsewhere. | §10 |
| Look | No fill of its own: the backdrop paints Black or Frosted behind the clear page panel; ink resolves through `\.islandFrosted`. | §1, §6 |
| Keys | A click pins; pinned, ←/→ and 1–9 pick tabs, Esc closes, ⌘R refreshes the page (on Home, every page), ⌘P toggles the pin. A horizontal two-finger swipe turns one tab. | `IslandPageKey`, `IslandPageSwipe` |

Deviations, numbered for review:

1. The badge is a compact outline keycap, the existing count chip, rather than a new red dot: §6 keeps colour for status, and a count reads without colour.
2. The cover is 64 points, a new token (§15), because no existing size fits a media cover.
3. The tab bar shows titles beside glyphs on every page count up to five; past that it would need glyph-only tabs, which nothing posts yet.

Reference: HIG Live Activities, "Present only the most essential content."

