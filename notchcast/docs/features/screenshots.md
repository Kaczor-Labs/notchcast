# Screenshots and the Capture Editor

The Screenshots add-on (`Tinycast/Features/Notchcast/Screenshots/`, switch `screenshot`, Settings › Notchcast › Capture) captures an area, a window or a display, and its Capture Editor annotates a capture before it is copied or saved (#936). Both share one module, `ScreenshotsModule`, and one seam to the Mac, `ScreenshotSystem`.

## Invariants

- **One thing at a time.** A capture session or an open editor makes the module busy; Capture Area, Capture Screen and Edit Last Screenshot are ignored until it ends. So the capture an editor holds is never replaced under it.
- **The original is never written over.** The editor draws marks over the untouched capture and renders a new image on Copy or Save; Save always writes a new file. The last capture is kept as PNG data (`lastCapture`), not a bitmap, so Edit Last Screenshot costs no full-size image between edits. It lives in memory only and goes when the switch goes off or the app quits.
- **What is seen is what is copied.** The canvas and the exported result draw through the same `AnnotationRenderer.draw`, in image pixels with the origin top left; the editor shows it scaled to fit.
- **The module closes the editor, never the editor itself.** The editor answers `CaptureEditorOutcome` (`.copy`, `.save`, `.discard`); the module writes the result and only then closes it, so a failed write reports through an island failure notice and leaves the editor open with every mark. Switching Screenshots off closes it and drops the last capture.
- **The model has no UI.** `Model/Annotation*.swift` (tools, marks, hit testing, undo history, key map, renderer) imports Core Graphics, Core Text and ImageIO only, and takes the pixels-per-point scale as a parameter.

## Using it

- **Edit after capture** (Screenshots option, off by default): every new capture opens in the editor instead of going to the screenshot destination.
- **Edit Last Screenshot** (launcher command, `command:nc-edit-last-screenshot`, symbol `pencil.tip.crop.circle`, owned by the `screenshot` switch): opens the last capture; with none yet it posts "No screenshot to edit yet.".
- **Tools**, each with a letter: Arrow `A`, Rectangle `R`, Ellipse `O`, Highlighter `H`, Text `T`, Pixelate `P`, Crop `C`. Three stroke widths (2, 4 and 8 points; text 14, 20 and 32 points) and eight colours; picking a width or colour restyles the selected mark too. A press on a mark's stroke selects and moves it, Delete removes it; a press inside an outline starts a new shape. Crop sets the output frame and is not a mark. Undo `⌘Z` and Redo `⇧⌘Z` cover every tool, restyles, deletes and the crop; one drag is one step.
- **Ways out:** Copy `⌘C` puts the PNG on the clipboard, Save `⌘S` writes it to the screenshot folder (Desktop when none is chosen) under the usual `Screenshot <date> at <time>.png` name, the Drag chip drags it into another app as a PNG file, and Escape discards. Copy and Save close the editor once the write succeeds. While text is typed, Escape and Return finish the text and `⌘C` copies the typed text.

## Window

`CaptureEditorPanel` is a borderless floating panel on the stock panel recipe (`panelScrim` over `GlassEffectView`, clipped to `Theme.Radius.dialog`), sized to fit the capture in 85% of the screen under the pointer, never narrower than `Theme.Size.panelWidth`; the tool groups sit on frosted capsules like the Notes formatting bar. It is not an island surface: the design system lets Screenshots own its capture surfaces (`notchcast/docs/design-system.md` §12). Every key goes through `AnnotationKeyAction` in `sendEvent`, so shortcuts need no focused control. Clicking away leaves it open.

## Tests

- `nc-Screenshots-annotation-test`: every tool's shape, hit testing per shape, undo and redo across every tool, the key map, and rendering to an image (arrow, outline, upright text, highlighter, pixelate, crop, PNG, Retina stroke).
- `nc-Screenshots-editor-test`: the module with a fake editor: capture an area, add an arrow and text, copy, and the pasted PNG has both; Escape writes nothing; a failed copy keeps the editor; Save writes a file; a capture while editing is ignored; switching off closes the editor.
- Not covered by a harness: the panel, canvas and drag-out views. Live check pending.
