# Agents

The Agents add-on (`Tinycast/Features/Notchcast/Agents/`, switch `agentsUsage`, Settings › Notchcast › Agents) shows every AI plan's usage as an island page (#1128): a column per machine, then an Other row for accounts shared by every machine. This Mac reads its Claude accounts and Codex itself; every machine's comes from `feed.json`, which the gate (`gate.py feed`, written on each Mac by `gate.py push`) puts in the feed folder.

## Invariants

- **Folders, then names, are the match.** The board finds this Mac's column by its name: machines `MBA`, `MBP`, `VPS`, and "This Mac's name" defaults to the computer name, which is `MBA` and `MBP` on the gate's Macs. Inside that column a Claude account and the feed's copy are one account when the feed gives the copy's `folder` (T3's config folder, such as `~/.claude_team`) and it is the same folder, compared with `~` expanded and an empty folder as `~/.claude`; a feed copy without `folder` (an older gate) matches by name. The merged card takes the gate's name (`C1`…`C6`) unless the name in Settings was typed: Settings' own default, "Claude" or the folder's name without its dot ("claude_team"), counts as not typed.
- **A Claude folder is passed as written, without a trailing slash.** Claude Code names its Keychain sign-in by a hash of `CLAUDE_CONFIG_DIR` exactly, so `~/.claude_team/` asks for a sign-in that `~/.claude_team` holds (#1189).
- **A card draws at most three meters** (`AgentBoard.meterCap`), the ones with least left in their usual order, and one line counts the rest ("2 more, lowest 100% left") unless the caption says the reading is old; VoiceOver reads every window. The open island is capped in height, so a taller card would cut the board's bottom row.
- **A shared account shows once, in Other.** The feed's `shared` list holds one account per provider (Codex, Grok, OpenCode, Antigravity). A local account that is also in `shared` leaves this Mac's column and merges into its Other card: matched by provider and name, or by provider alone when each side holds one account of it, since Notchcast names its Codex "Codex" and the gate takes T3's name. The card keeps the feed's name.
- **This Mac's reading wins** over the feed's copy of the same account unless it failed or is stale beside a fresher copy. The winner keeps its numbers; a reset credit or extra-usage budget it lacks comes from the other copy, so neither comes and goes.
- **Feed readings dim later.** A card read on this Mac dims after 10 min (`AgentBoard.staleAfter`); one from the feed after 25 min (`feedStaleAfter`): up to 10 min old when pushed, a 5 min push, and T3's own delay.
- **Numbers read left.** "55% left", the fill what is left.

`Tests/nc-Agents-model-test.swift` holds the board against a feed cut from `gate.py feed` (`boardWithGateFeed`) and the folder match (`boardMatchesFolders`); `Tests/nc-Agents-board-render-test.swift` (hosted-only) renders the MBP's board before and after the match and checks it fits the island.

## Hand test

On each Mac: Settings › Notchcast › Agents shows This Mac's name as `MBA` (`MBP`) and each Claude folder T3 uses; with `feed.json` from the gate in place, open the Agents page and check that each machine shows one column, no account shows twice (Codex only in Other), and other machines' cards are not dimmed while the gate pushes.

Known gap: two accounts of one provider in `shared` collapse into one card (chad-v2#361).
