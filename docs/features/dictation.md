# Dictation (experimental)

Dictation is off by default. A user-selected global shortcut records from the chosen microphone,
transcribes locally and sends the result through `TextInjector`. Parakeet Ultra (quality) and Redux
(lightweight) support 25 languages. Qwen3-ASR 0.6B and 1.7B support 30 languages and 22 Chinese dialects.
No model is bundled. The Settings pane downloads a pinned Core ML conversion on request.

Recognition uses Apple's Core ML and Accelerate, with no external library. Each model family has
its own adapter inside the bundled helper; both variants share that family's implementation.
The same audio-to-text channel feeds the coordinator regardless of which model is selected.
Parakeet variants declare their joint model, blank token and encoder placement in `DictationModel`, alongside the pinned
download metadata. A new variant must match the adapter's tensor shapes and TDT decoding contract;
sharing a model-family name alone does not establish compatibility.
Redux is the default. Redux's encoder uses CPU/GPU to avoid the several-minute initial Neural Engine
compilation of its 2-bit weights; Ultra's encoder and both variants' decoder/joint use CPU/Neural Engine.

## Invariants

- `AppCore` owns the model store and coordinator. The microphone session, panel and focused target
  belong only to `DictationCoordinator`; no recording starts merely by launching Tinycast or opening
  Settings.
- The enable switch is consent. It explains microphone and Accessibility access before enabling,
  and, like every Dictation preference, is excluded from backups so importing settings cannot arm
  a global recording shortcut.
- Microphone status appears in Permissions and the Dictation pane. Neither pane prompts on display;
  only a user action requests access, while revoked access is refreshed from macOS.
- `HotKeyAction.dictation` uses the shared recorder and conflict handling. Toggle mode accepts any
  binding; hold-to-talk accepts a Carbon chord or a single physical modifier, including Globe.
  Modifier holds begin after 250 ms alone and reserve their key across single and double taps.
  Another modifier, key or click cancels the hold without inserting text. Double taps require toggle.
- Carbon or the shared modifier monitor reports release to stop a held recording. Return finishes,
  Escape cancels. Opening a shortcut recorder cancels a held recording before pausing its shortcuts.
  A session token
  prevents a cancelled or superseded transcription from inserting text later.
- AI Chat's composer mic is always click-to-toggle into that field: `toggle(into:)` targets its
  `ComposerTextView` in process whatever has focus, `field` tells only that button it is running, and
  its transcript is inserted whatever the destination setting, never copied.
  Switching chats or closing the composer cancels only the session targeting that editor, including
  one started by a shortcut. The session token is checked again when queued insertion runs.
- The nonactivating panel preserves the target app. Text insertion reuses `TextInjector`, including
  its temporary clipboard ownership, focus, secure-input and protected-target checks. Copy-only
  writes the plain transcript without reading the caret; paste-and-copy writes the persistent copy
  after delivery or a failed insertion.
- The Liquid Glass capsule displays 21 fixed frequency bands driven by the microphone, sampled at
  most 20 times per second through a reused 512-point Accelerate transform on the capture queue.
  Logarithmic bands span 32–5000 Hz so speech sits nearer the middle. Smoothed levels taper and
  fade only toward the edges, without a center peak or mirroring.
  Transcription replaces them with a smaller wave whose white center fades to gray, moving left to
  right at up to 30 frames per second.
  Reduce Motion pauses the processing timeline; closing the panel releases its hosting view so no
  animation continues while hidden.
- Dictation fades the default output's software volume down by about 90% from shortcut press, or from
  the start cue when Play sounds is on, then restores
  it on completion, cancellation and normal quit. An unsupported output is left untouched, as is a
  volume the user changes during capture. Before each fade step, a bundle-ID Application Support
  file records the device UID, original volume and the values before and after that step.
  Relaunch restores the original device only if its volume still matches that record, including
  when Dictation is disabled. An unavailable device keeps its record for a later attempt; new ducking
  waits for that recovery. File writes run off-main and finish before the hardware changes.
- Play sounds is on by default. When on, macOS's `dt-begin.caf` plays on the microphone's first samples
  and `dt-confirm.caf` when recording stops (release, toggle, Return or the length limit); cancelling
  stays silent. These are internal resources in `AssistantServices.framework`, not bundled audio;
  their location is undocumented, and a missing sound is silently skipped without blocking dictation.
  A Bluetooth headset drops output while it switches to its microphone, sometimes after the first
  samples arrive, so with a Bluetooth microphone the start cue waits half a second more. With sounds
  on, for any microphone, ducking starts with the start cue instead of at the press, and never for a
  session cancelled meanwhile. On stop the volume is restored at once instead of faded, so the cue
  plays at full volume before the microphone closes and a headset switches back. Ducking is device-wide, so
  media at full volume can mask the start cue. Through speakers a cue can reach the recording; it is
  not removed.
- The microphone, waveform, permissions and insertion stay in Tinycast. Model loading, audio
  features and decoding run in `Tinycast Dictation` (`Tinycast Dev Dictation` in Debug), started
  only for transcription. Main-app state never retains Core ML models or imports the adapters.
  The helper is an embedded accessory app with no bundled icon, Dock item or windows.
- Core ML models live under this build's bundle-ID cache. After one minute idle by default, the
  store terminates and reaps the helper, releasing its model memory. Other delays or Never are
  selectable. Switching models reaps the old helper before loading the next; removing a loaded model
  stops its helper before deleting the directory and blocks new requests for that model meanwhile.
  Cancelling an active transcription, failed inference and normal quit stop the helper; late results cannot paste.
- Audio stays in memory, bounded to five minutes of mono 16 kHz Float32 samples. Pipes carry
  bounded JSON control messages and binary audio; recordings are never written to disk or sent
  over the network. Long recordings split near a quiet passage without overlapping samples.
- Live insertion is off by default and flushes at speech pauses, or after eight seconds of
  unpaused speech at the latest. While recording, the coordinator transcribes the audio since the
  last flush and pastes each chunk through `TextInjector` in order; finishing lets queued chunks
  land, then transcribes only the remainder. A cancelled chunk keeps its audio behind for that
  final pass, and a copy destination receives the assembled text. Chunk cuts fall near a
  quiet passage, like long recordings do, and copy-only sessions never start the live loop.
- Every flush re-transcribes from a pause-anchored overlap start and drops the repeated head
  word-wise, tolerating fragment words and case or punctuation variants, so word splits at
  chunk cuts rarely duplicate. When the app exposes no caret, spacing and casing fall back to
  the already pasted text instead of gluing chunks together. A chunk that fails to paste is
  reported once at finish, never silently lost. Pasted text is never revised: matching Siri-style
  correction would mean deleting and retyping inside foreign apps, which is fragile next to a
  moving cursor and the user's own edits.
- Model files download through a feature-private ephemeral session without a disk URL cache.
  Repositories and revisions are explicit in `DictationModel`; each download is staged and
  published only when all required files arrive, their sizes agree with the manifest and large-file
  SHA-256 checksums match. Settings shows combined byte counts and a percentage in a full-width
  progress row for the selected model. Download delegate callbacks report actual transferred bytes,
  with intermediate updates limited to one per 100 ms per file; each verified file reports its final
  count immediately. Progress observation stays in the download row. Switching
  selection leaves its download running in the background. Cancellation and
  normal quit remove staging files without publishing a partial model. A new download removes stale
  staging directories left by a crash or forced quit, without touching installed models or other files.
  A nonblocking file lock covers cleanup through publication, rejecting another download sharing
  the same cache root. Its empty lock file stays in place; macOS releases the lock on process exit.
- An installed Qwen model exposes a language hint; Auto leaves language detection to the model. Parakeet
  does not accept a language hint. Neither adapter exposes user vocabulary. Qwen prepares its fixed
  prompts and supported language hints once, then retains only the tokenizer's decoding tables
  and prepared tokens, not the BPE encoding rules.
- The `Model/` folder imports Foundation only. Context-sensitive spaces and capitalization are a
  pure decision driven by text around the caret. Capitalization adapts by default and can be disabled
  without disabling contextual spaces; if an app does not expose that context through
  Accessibility, the plain transcript is inserted without guessing.

## Island states

Notchcast shows a dictation on the island instead of the capsule (#960). The capsule's panel still opens, because it is what catches Return and Escape without activating Notchcast, but `NotchcastDictationIsland` (`Tinycast/Features/Notchcast/`) empties it and sets its alpha to 0 before it shows, so nothing of it is drawn. The capsule's view code stays in the tree, unshown, so upstream edits to it never conflict.

- `DictationIslandSession` (`Tinycast/Features/DictationIsland/Model/`) is the state machine: recording, transcribing, cleaning up, then pasted, copied, no speech or failed. `IslandNotice(dictation:)` turns each state into the one notice (`notchcast.dictation`) that `NotchcastDictationIsland` reposts through `IslandPresenting`; it opens no window of its own.
- Recording is a titled progress notice: its ring is the microphone level in 12 steps, its readout the elapsed time as `m:ss`, its text the hints "Return to Paste · Esc to Cancel" ("Return to Copy" for a copy-only destination). Without a notch the pill reads ring, time, hints. On a notch the ring sits left of it and the time right of it; the hints come out below the notch for one message dwell and again on hover (design system §10).
- Transcribing and cleaning up are compact progress notices, a glyph beside the notch and glyph and word without one. Results are plain notices with the stock dwell: "Pasted", "Copied", "No Speech Detected"; "Dictation Failed" is a failure notice (red glyph, 4 s). Escape clears the island at once.
- The hooks are added lines only. `DictationPanelController.show` hands over the capsule and its `DictationDisplayState`, whose observed `levels` and `phase` drive the ring, the clock and the move to transcribing, so the level stream is the only clock. `DictationCoordinator` has two closures, set by `NotchcastDictationIsland` and empty in the harnesses that compile the coordinator alone: `didFinish` from the delivered, copied and no-remainder paths, and `didReset` from `reset`. A session that ran to its end with no outcome failed; any other end was a cancel.
- A failure's reason still shows in the stock report under the island; the island only says that it failed. A result or failure that ends under the launcher or a question is dropped rather than shown late, and a recording started from a palette field's own mic shows on the pill only once the palette closes.
- Cleaning up has no caller yet: `NotchcastDictationIsland.cleaningUp()` is the entry for the cleanup step (#957) to call before it runs.

`nc-DictationIsland-session-test` checks every transition, the clock and ring steps, each state's notice, cancel, failure and the covered drops, on injected timestamps with no microphone. `nc-Notchcast-island-audit-render-test` renders every state in both forms (`960-*.png`; `NC_AUDIT_LOOK=frosted` for Frosted). Not verified: the live flow on a Mac (Return and Escape through the emptied panel, the ring against a real microphone, a real notch).

## Validation

`DictationCueTests` checks system resource paths, playback ordering and missing sounds without audio output.
`DictationFieldTests` checks composer switching and teardown, scoped cancellation, delayed insertion and
the order of sound cues against ducking
with synthetic capture and real AppKit editors, without recording audio or touching the shared clipboard.
`DictationTests` checks formatting and model options; `DictationInferenceTests` checks score selection,
byte BPE, Fourier/mel features, listening bands and audio partitioning without downloading a model. `DictationWorkerTests`
exercises framed IPC, worker reuse/switching, removal, cancellation and broken pipes with a fixture.
An in-process URLProtocol fixture checks byte progress before the first file completes, combined
progress and atomic installation for both families, including cancellation, stale staging cleanup
and competing downloads on shared or independent cache roots, without sockets or timed waits.
`DictationVolumeTests` uses private files and injected audio controls to verify crash recovery
before and after fade steps, user volume changes, output switching, failed writes and rapid cancellation,
without changing the system volume or downloading a model.

Also exercise all four real models, short and long recordings, downloads/removal, initial microphone
grant and denial, hold/toggle shortcuts, Return/Escape, output destinations, live insertion on and off, surrounding text with
capitalization adaptation on and off,
model switching and idle release/reload. Check both processes in Activity Monitor, and validate
Debug and Release helper names, signatures and architecture slices. Model conversions and their
source licences must be reviewed before distribution; swapping one requires real-audio validation.

For reproducible real-model measurements, build Debug, install the models through Settings, then run:

```sh
./Scripts/benchmark-dictation.sh /path/to/sample.wav
```

The optional tool converts the supplied audio to mono 16 kHz and launches the built helper directly,
without using the microphone, clipboard or settings. It reports load and transcription times, sampled
helper `phys_footprint` in decimal MB and the recognized text, first with a fresh helper and then with
its model already loaded. macOS's file and Core ML caches remain untouched; a fresh helper is not a
cold disk-cache measurement. The 50 ms memory samples are not a guaranteed absolute peak.
Use the same audio, build configuration and otherwise idle machine for comparisons.

Optional arguments select a helper `.app`, model directory and one model's raw identifier instead of
all four. This tool is outside the deterministic suite and app targets; it neither downloads models
nor adds bundled resources.
