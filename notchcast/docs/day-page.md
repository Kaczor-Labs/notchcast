# Day page

The Day add-on (`Tinycast/Features/Notchcast/Day/`, switch `dayPage`, "Day in the Island" in Settings › Notchcast › Mac Tweaks, off by default) puts a Day page in the open island: the weather now and for the next five hours, the user's market quotes, and today's events (#978, decisions 946-7 and 946-10). It is an add-on under [addons.md](addons.md): one folder and one registry line.

## Invariants

- **Weather and markets never enter the closed island.** The module posts a page and nothing else: no status, no notice, no level. `nc-Day-module-test` fails on any of them.
- **Every fetch goes through `DayNetwork`**: a private `.ephemeral` session with `urlCache = nil`, https only, 20 s timeout per request and 30 s in all, answers over 512 KB refused. Nothing fetched is written to disk; the last values live in memory and go when the switch goes off or the app quits.
- **Nothing is fetched until the user asks for it.** No city means no weather request, no symbols means no quote request, and the switch off means no request at all.
- **Parsing, refresh times, the offline state and every word on the page live in `Model/`**, which imports Foundation only and takes the clock, calendar and locale as parameters.
- **The add-on draws nothing and reads no calendar itself.** It posts an `IslandPage`; events come from stock Calendar through `context.calendar` and open its My Schedule screen.

## What it shows

| Where | What |
| --- | --- |
| Page, weather | A row with the glyph, temperature and condition over the city, then one row per coming hour (up to five) with its glyph and temperature. Degrees follow the Mac's region (Fahrenheit in the US). |
| Page, markets | A "Markets" header, then one row per symbol: price and the change since the previous close with an arrow (▲ ▼), a dash while a symbol has no quote. |
| Page, today | A "Today" header, then up to five events not yet over (all-day first) with "All day", "Now", "in 25 min" inside the hour before a start, or the start time; more are one counted row. Every row opens My Schedule. |
| Home line | The event under way or next up, "in 25 min · Design review" (the time first, so a long title cannot cut it off), with the weather as its detail; a click opens My Schedule. With no event today: the weather with the first quote as its detail, and a click opens the page. Only live readings go on the line: a stale feed (its last fetch failed, or its reading is old, below) is left out, and with neither live and no event it says "Unavailable". |
| Closed island | Nothing. |

A section with nothing chosen is left out, and with no section the page posts nil and leaves no tab. Command-R fetches both feeds at once.

## Sources

| Data | Source | Notes |
| --- | --- | --- |
| Weather | Open-Meteo forecast API (`api.open-meteo.com`) | Free, no key. Current reading plus hourly temperature, WMO weather code and day flag. |
| City | Open-Meteo geocoding API (`geocoding-api.open-meteo.com`) | Free, no key. Asked once when the user enters a city; the name and coordinates are kept in the `.notchcast` suite (`dayPlace`). No Location Services. |
| Stocks, crypto, currencies | Yahoo Finance chart endpoint (`query1.finance.yahoo.com/v8/finance/chart/<symbol>`) | Free, no key, one request per symbol. Not a documented API: Yahoo can change or close it. Symbols are Yahoo's (`AAPL`, `BTC-USD`, `EURUSD=X`, `^GSPC`), kept as typed in `daySymbols`, at most eight. |

Requests carry the app's default user agent and nothing about the user beyond the coordinates and symbols themselves.

## Refresh and offline

`DayModule` (`Service/`) watches the Day page through `IslandPresenting.watchPages`, which says when the open island shows Home or Day. Only then does it wake once a minute, redraw the page from what it has (so countdowns and the hour rows move) and fetch a feed when `DayBoard` says it is due: weather every 30 minutes, markets every 5 (decision 946); failed weather one minute later, failed markets after their 5. Hidden, no timer runs and nothing is fetched; shown again, a feed older than its interval is fetched at once. A city or symbols set while the island is closed is fetched the next time Home or Day shows. One load runs at a time, owned by the module rather than the timer: hiding the page stops only the timer, so a load under way finishes, is recorded and posts, and short visits never start the requests again. A load that returns after the switch went off (`stop` cancels it), or for a city or list since changed, is dropped. A page equal to the last one posted is not posted again.

A failed fetch, or an answer that does not parse, marks that feed stale (`isOffline` in the model: the source may fail while the Mac is online); so does a last answer older than its interval plus one minute tick (`DayBoard.staleGrace`), as after a long hidden spell, until the new fetch returns. Stale, a feed drops out of the Home line, keeps its last values and says when they were taken ("Updated 15:32"): beside the weather, or on the Markets header. Stale before any answer, the section shows "Unavailable" in place of values. Markets count as one round: if any symbol answers, every symbol shows this round's answer and one that failed shows a dash, never an old price; only a round where none answers keeps the last quotes. There is no spinner.

## Settings

Under the switch: **City** (looked up on Return; an unknown city says so and keeps the old one; empty clears it) and **Symbols** (comma or space separated, applied on Return, normalised to upper case without repeats). A note under them says events come from the Calendar feature and need its calendar access; the add-on never asks for that access itself.

## Sources of code

`Model/DayAgenda.swift` is adapted from Vorssaint's notch calendar (GPL-3.0-or-later, `vorssaint/vorssaint-utils@89d2626`): which events belong to a day, their order, the next one and a start as text. It keeps Vorssaint's notice and has its lines in `notchcast/licenses/borrowed.md`. Not taken: the calendar views (an add-on describes a page, the island draws it), the month grid and week strip, the EventKit reader (events come from stock Calendar) and the closed-island countdown (the island's own meeting glance does that). Vorssaint has no weather or markets.

## Proof

- `Tests/nc-Day-model-test.swift`: parsing of the forecast, city search and quotes from fake responses, refused answers, the symbol list, the refresh clock, the visibility rule, the quote round, the offline rules, the Home line with a stale feed, a reading marked by age, today's events and every row of the page, with an injected clock, calendar and locale.
- `Tests/nc-Day-module-test.swift`: the module as its hook starts it, on a fake network with an injected clock and a sleep that takes no time: what is fetched when, nothing while the page is hidden and what is due once it shows again, the retry after a failure, offline with and without last values, Command-R, the My Schedule action, a changed list, the city lookup, switch off, a load that returns after switch-off, and ten short visits during one load that start its requests once, then post its answer.
- `Tests/nc-Day-render-test.swift`: PNGs of the page and Home, online and offline, in both forms on Black and Frosted (`978-*`, uploaded by CI as `island-renders-<shard>`).

## Deviations, numbered for review

1. Hidden means no fetch at all, so a page opened after a long while first shows the old values, marked "Updated", until the fetch it starts returns.
2. Market changes carry no green or red: `IslandPageRow` has no tone, so direction is the arrow alone. Colour needs a tone on that value in the island core.
3. The hours are one row each; a compact strip would be a new block in the pages core.
4. The switch sits in Mac Tweaks, the one shown tab that fits; a tab for island pages is a core change.
5. Last values are not kept across a relaunch: a failure at launch shows "Unavailable" until the first answer.
6. Events follow stock Calendar within a minute, not at once.
7. The quote source is unofficial. A documented one needs an API key (Finnhub, Twelve Data and Alpha Vantage offer keyed tiers), which is a decision for the owner.

Not verified: any of it live (real answers through `DayNetwork`, the page in the running island, the Settings rows, the My Schedule click, VoiceOver); CI compiles, runs the harnesses and renders it.
