# Agents

The Agents add-on (`Tinycast/Features/Notchcast/Agents/`, switch `agentsUsage`, Settings › Notchcast › Agents) shows every AI plan's usage as an island page (#1128): a column per machine, then an Other row for accounts shared by every machine. This Mac reads its Claude accounts and Codex itself; every machine's comes from `feed.json`, which the gate (`gate.py feed`, written on each Mac by `gate.py push`) puts in the feed folder.

## Invariants

- **Names are the match.** The board finds this Mac's column by its name and an account by its name, so both must be the gate's: machines `MBA`, `MBP`, `VPS`; Claude plans `C1` and `C2` (MBA), `C3` = `~/.claude` and `C4` = `~/.claude_team` (MBP), `C5` and `C6` (VPS). "This Mac's name" defaults to the computer name, which is `MBA` and `MBP` on the gate's Macs; the Claude account names in Settings are set by hand, since nothing on a Mac says which plan it is.
- **A shared account shows once, in Other.** The feed's `shared` list holds one account per provider (Codex, Grok, OpenCode, Antigravity). A local account that is also in `shared` leaves this Mac's column and merges into its Other card: matched by provider and name, or by provider alone when each side holds one account of it, since Notchcast names its Codex "Codex" and the gate takes T3's name. The card keeps the feed's name.
- **This Mac's reading wins** over the feed's copy of the same account unless it failed or is stale beside a fresher copy. The winner keeps its numbers; a reset credit or extra-usage budget it lacks comes from the other copy, so neither comes and goes.
- **Feed readings dim later.** A card read on this Mac dims after 10 min (`AgentBoard.staleAfter`); one from the feed after 25 min (`feedStaleAfter`): up to 10 min old when pushed, a 5 min push, and T3's own delay.
- **Numbers read left.** "55% left", the fill what is left.

`Tests/nc-Agents-model-test.swift` holds the board against a feed cut from `gate.py feed` (`boardWithGateFeed`).

## Hand test

On each Mac: Settings › Notchcast › Agents shows This Mac's name as `MBA` (`MBP`) and the Claude accounts named as above; with `feed.json` from the gate in place, open the Agents page and check that each machine shows one column, no account shows twice (Codex only in Other), and other machines' cards are not dimmed while the gate pushes.

Known gap: two accounts of one provider in `shared` collapse into one card (chad-v2#361).
