# Agents page and AI plan left

The Agents add-on (`Tinycast/Features/Notchcast/Agents/`, switch `agentsPage`, "Agents in the Island", off by default) shows on the island who waits for you and what they ask, who works and under whom, and how much of every AI plan is left (#976, decisions 946-3, 946-4, 946-5, 946-8). Notchcast is only the reader: a helper on the agents' side publishes two small JSON files, and the add-on draws them through the island's page API.

## Invariants

- **Notchcast only reads the two feed files.** `agents.json` and `usage.json` in `Feeds/` inside Notchcast's own Application Support folder (`~/Library/Application Support/app.notchcast/Feeds/`, Debug `app.notchcast.dev`; Settings shows the path). It makes that folder and writes nothing else there. It never reads another app's files or databases: a symlink in place of a feed file is not followed, and a pipe or folder is not read (`AgentsFeedReader`).
- **A stale feed is never shown as live.** Past `updatedAt + staleAfter`, or dated `staleAfter` or more ahead of the Mac's clock, its last values stay on the page under a "Stale" row with their time, and it gives no badge, no ask line and no closed-island status.
- **Percent is always percent left.** `percentLeft` is shown as it comes, rounded down; nothing is derived from "used".
- **Only https and app URL schemes open.** `openURL` values with `http`, `file`, `javascript`, `data`, a share, shell, call (`facetime`, `tel`) or message (`sms`, `mailto`) scheme are dropped at parse time (`AgentsFeedFields.refusedSchemes`).
- **The add-on describes, the island draws.** Everything goes through `context.presenter`: `setPage`, `setStatus` and `post`. It opens no window and adds no view to the island.

## The feed files (for the producer)

The helper writes each file whole: a temp file in the same folder, then a rename onto the name. The add-on watches the folder (`AgentsFolderWatcher`, a `DispatchSource` on the folder itself, no polling), so a rename shows at once. Dates are ISO 8601 (`2026-11-18T10:00:00Z`, fractional seconds allowed). Unknown fields are ignored. Samples with invented names: `Tests/nc-Agents-feeds/agents.json` and `usage.json`.

`agents.json`, schema `notchcast.agents/1`:

| Field | Meaning |
| --- | --- |
| `schema` | exactly `notchcast.agents/1`; anything else reads as "No data" |
| `updatedAt` | when the helper wrote the file; required |
| `staleAfter` | seconds the file stays live, 5 to 86400; missing means 300 |
| `openURL` | where "Open" leads for an agent with no link of its own |
| `agents[]` | at most the first 100 entries count |
| `agents[].id`, `title` | required; an entry without either is dropped. `title` says what it works on, in plain words |
| `agents[].role` | `coordinator`, `worker` or `agent`; unknown reads as `agent` |
| `agents[].parent` | the `id` of the agent it works under |
| `agents[].group` | a short label shown before the status text of a coordinator, such as a project |
| `agents[].status` | `working`, `waiting`, `done`, `failed` or `idle`; unknown reads as `idle` |
| `agents[].statusText` | one plain sentence |
| `agents[].needsInput` | `true` puts the agent first on the page and in the badge |
| `agents[].ask` | what it asks, in plain words |
| `agents[].since` | when the current status began |
| `agents[].openURL` | where "Open" leads for this agent |

`usage.json`, schema `notchcast.usage/1`:

| Field | Meaning |
| --- | --- |
| `schema`, `updatedAt`, `staleAfter` | as above |
| `meters[]` | one per plan window and account; at most the first 24 count |
| `meters[].id` | stable name; missing means the label |
| `meters[].label` | required, such as "North · week" |
| `meters[].percentLeft` | required number, kept within 0 to 100 |
| `meters[].resetsAt` | when the window renews |
| `meters[].warnBelow` | percent left under which the closed island warns; missing means 20 |

Limits: 256 KB per file (a larger one is not read past the limit and shows "No data"), ids 100 characters, titles, groups and labels 80, sentences 200, links 2048; longer text is cut with an ellipsis and line breaks become spaces.

## What shows

- **Page** (`AgentsBoard.page`, order 0, posted as `IslandPage` id `agents`): agents that need input first, each with its ask and "Open"; then every working, waiting or failed agent, a coordinator above its workers in the feed's order (finished and idle ones are left out, a coordinator stays while one of its workers lists); at most 8 rows, the rest counted as "N more"; then one bar per meter with "62% left · resets in 3h 19m". A row with a link is a button that opens it. Neither file present: no page and no tab. A malformed, oversized or wrong-schema file: a calm "No data" row naming the file.
- **Badge**: the count of agents that need input, on the Agents tab; it moves the Home line to the top.
- **Home line**: "N agents waiting" with the lowest plan as detail, else "AI plan 62% left" (the lowest meter) with "N agents working" as detail.
- **Closed island** (`AgentsBoard.status`): while anyone needs input, a glyph and the count, ranked `IslandRestRank.agentWaiting`, which takes the pill from the meeting glance; otherwise, while a meter is under its `warnBelow`, a gauge glyph and that percent, ranked `lowPlan`. Beside a notch that is all that shows.
- **Ask line**: a request not seen before posts "Agent needs you: <title>" once as a notice (2.4 s; below the notch on a notched display), or "N agents need you" when several arrive together. An ask is known by agent id and ask text (`AgentsAskLog`), so the same ask never repeats, a feed going stale and live again does not repeat it, and a new question does show.
- **Keys**: Command-R reads both files again; Command-P pins, as on every page.
- **Refresh**: on every folder event, and on one wake-up (`AgentsBoard.nextRefresh`) at the moment a feed goes stale or after a minute, so elapsed times and countdowns turn. Unchanged values post nothing.

Closed-island priority (946-3) is `IslandRestRank` in `Features/Island/Model/IslandPresentation.swift`: agent waiting > meeting > music > system hot > low AI plan > any other status. A status carries its rank; the row is ordered lowest first, so the highest is the one the pill keeps when the wing overflows and the one a click acts on. Only this add-on posts ranked statuses today; music and system-hot have a rank waiting for #930 and #977.

## Code

`Model/` is pure (Foundation only, clock and region injected): `AgentsFeed.swift` (both schemas, lenient parsing, limits, staleness), `AgentsBoard.swift` (page, Home line, badge, closed-island status, ask line, next refresh), `AgentsFormat.swift` (percent, durations, times; adapted from Vorssaint). `Service/AgentsModule.swift` wires them to the presenter through `AgentsSystem`, a struct of closures (files, watcher, wake-up, opener, region) that `AgentsSystem+Live.swift` binds to the Mac. The feed files are read on the main actor: two local files of at most 256 KB each, on a folder event.

## Proof

`nc-Agents-model-test` covers parsing, limits, links, staleness, the page, the badge, the closed-island rank and the ask log with injected files and clock. `nc-Agents-module-test` drives the shipped module through `AgentsAddon.makeModule` with a fake folder, watcher, clock and wake-up, and runs the shipped file reader against scratch files (size cap, symlink and pipe refused). `nc-Agents-render-test` renders the page, Home, the badged tab, the stale and no-data states and the closed island's badge, ask line and low-plan status from the sample feeds, in both forms on Black and Frosted (`976-*.png`, uploaded by CI as `island-renders-<shard>`).

Not verified: anything live (the folder watcher on a real rename, hover and the click on "Open", the notice on a real notch, the status taking the pill from a real meeting glance), VoiceOver, and a producer other than the sample files.
