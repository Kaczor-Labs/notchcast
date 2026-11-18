# Screenshots and the Capture Editor

The Screenshots add-on (`Tinycast/Features/Notchcast/Screenshots/`, switch `screenshot`, Settings › Notchcast › Capture) captures an area, a window or a display, and its Capture Editor annotates a capture before it is copied or saved (#936). Both share one module, `ScreenshotsModule`, and one seam to the Mac, `ScreenshotSystem`. The editor is ported from Vorssaint's screenshot editor (see [Derived from Vorssaint](#derived-from-vorssaint)): the issue decides what it does, Vorssaint how.

## Invariants

- **One thing at a time.** A capture session or an open editor makes the module busy; Capture Area, Capture Screen and Edit Last Screenshot are ignored until it ends. So the capture an editor holds is never replaced under it.
- **The capture is never written over.** The editor works on its own `AnnotationDocument`; a crop cuts the document's image, never the kept capture, and Save always writes a new file. The last capture is kept as PNG data (`lastCapture`), not a bitmap, so Edit Last Screenshot costs no full-size image between edits. It lives in memory only and goes when the switch goes off or the app quits.
- **What is seen is what is copied.** The canvas and the result draw marks through the same `AnnotationRenderer.draw`, in image pixels with the origin top left; the editor shows it scaled to fit. Pixelate paints from a mosaic of the capture sampled once per image for the canvas and afresh for the result, so the blocks match while their noise differs.
- **The module closes the editor, never the editor itself.** The editor answers `CaptureEditorOutcome` (`.copy`, `.save`, `.discard`); the module writes the result and only then closes it, so a failed write reports through an island failure notice and leaves the editor open with every mark. Switching Screenshots off closes it and drops the last capture.
- **The model has no UI.** `Model/Annotation*.swift` (tools, marks, geometry, gestures, hit testing, undo history, key map, renderer) imports Core Graphics, Core Text, ImageIO and UniformTypeIdentifiers only; the pixels-per-point scale and the mosaic's random generator are parameters.

## Using it

- **Edit after capture** (Screenshots option, off by default): every new capture opens in the editor instead of going to the screenshot destination.
- **Edit Last Screenshot** (launcher command, `command:nc-edit-last-screenshot`, symbol `pencil.tip.crop.circle`, owned by the `screenshot` switch): opens the last capture; with none yet it posts "No screenshot to edit yet.".
- **Tools**, in Vorssaint's rail order, each picked by its digit: Select `1`, Arrow `2`, Pixelate `3`, Crop `4`, Text `5`, Rectangle `6`, Highlighter `7`, Ellipse `8`. The editor opens on Arrow, red, medium. Eight colours, three thicknesses (2, 4 and 7 points) for arrows and outlines, and text sizes from 10 to 96 points (19 by default); the style row shows only what the tool, or the selected mark under Select, uses, and a change restyles the selected mark as one undo step.
- **Marks:** a new mark stays selected; a press on the selection moves it under any tool, its grips resize a box and move an arrow's ends. A click on a mark's edge picks it and switches to Select; a click on text opens it for typing. A press inside an old box with nothing selected starts a new shape. A click that never moved leaves no shape. Delete removes the selection.
- **Crop** starts on the whole capture; drag a new frame, move it or pull its grips, then press Return or the Crop button. It cuts the image and moves every mark with it.
- **Undo** `⌘Z` and **Redo** `⇧⌘Z` cover every tool, moves, restyles, deletes, text edits and the crop, up to 60 steps.
- **Ways out:** Copy `⌘C` (or Return with no crop pending) puts the PNG on the clipboard, Save `⌘S` writes it to the screenshot folder (Desktop when none is chosen) under the usual `Screenshot <date> at <time>.png` name, the Drag chip drags it into another app as a PNG file, and Discard `⌘⌫` closes without writing. Escape backs out one level at a time: the text being typed, then Crop, then the selection, then the editor itself. Copy and Save close the editor once the write succeeds; text still being typed is part of the result. While text is typed every key belongs to the field.

## Window

`CaptureEditorPanel` is a borderless floating panel on the stock panel recipe (`panelScrim` over `GlassEffectView`, clipped to `Theme.Radius.dialog`), sized to fit the capture in 85% of the screen under the pointer, never narrower than `Theme.Size.panelWidth`. Vorssaint's layout: the actions above (Undo, Redo, Drag, Discard, Save, Copy), the tool rail beside the canvas, the style row below; the rail and the style groups sit on frosted capsules like the Notes formatting bar. It is not an island surface: the design system lets Screenshots own its capture surfaces (`notchcast/docs/design-system.md` §12). Every key goes through `AnnotationKeyAction` in `sendEvent`, so shortcuts need no focused control. Clicking away leaves it open.

## Derived from Vorssaint

Ported from `vorssaint/vorssaint-utils@89d2626` (GPL-3.0-or-later); each file keeps Vorssaint's notice and has its line in `notchcast/licenses/borrowed.md`:

- `AnnotationMark.swift` from `ScreenshotSupport.swift`: tools and their order, colours, thicknesses, text sizes, handles, crop snapping, arrow geometry, block size.
- `AnnotationDocument.swift` and `AnnotationDocument+Gestures.swift` from `ScreenshotEditorController.swift` (its editor model): undo snapshots, styling the selection, text commit, crop, presses, drags, taps and hit testing.
- `AnnotationKeyAction.swift` from the same file's key handling.
- `AnnotationRenderer.swift` from `ScreenshotRenderer.swift`: the marks, the noisy mosaic, the flattened image and the PNG with its DPI.
- `CaptureEditorView.swift`, `CaptureEditorCanvas.swift` and `CaptureEditorControls.swift` from `ScreenshotEditorView.swift`: the layout, the canvas gesture, the inline text field and the rail.

Left out, as #936 does not ask for them: Vorssaint's pen, line, sticker, counter, redact, spotlight, expand canvas and pasted images, blur styles and strengths, arrow styles, shadows, backdrops, watermarks, text recognition, pins, sharing, the quick preview and custom tool keys. Notchcast's own: the module wiring and `CaptureEditorOutcome`, the panel, the session, the drag export, the module harness, and Core Text in place of AppKit text so the model stays pure.

## Tests

- `nc-Screenshots-annotation-test`: every tool's mark, clicks that leave nothing, hit testing, moving and resizing, text editing, undo and redo across every tool, restyles, moves, the crop and deletes, the key map and Escape's levels, and rendering to an image (arrow, outline, upright text, highlight, pixelate, crop, PNG DPI, Retina width).
- `nc-Screenshots-editor-test`: the module with a fake editor: capture an area, add an arrow and text, copy, and the pasted PNG has both; Discard writes nothing; a failed copy keeps the editor; Save writes a file; a capture while editing is ignored; switching off closes the editor.
- Not covered by a harness: the panel, canvas and drag-out views. Live check pending.
