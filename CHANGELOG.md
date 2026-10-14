# Changelog

## 0.1.0, not released yet

The first version.

- The menu bar item: the weekly percentage and a five cell bar, dimmed when the figures are older than an hour.
- The Claude tab: the weekly and the 5h window with pace in words and clock time, the open sessions and their context, tokens by model, project and session from the local transcripts, the list price equivalent, week over week.
- The Mac tab: CPU, GPU, memory with pressure and swap, battery, the busiest processes.
- Settings: Mac figures in the bar, the two nudges, the list price equivalent, and one row to install or remove the status line entry.
- The status line hook: installed only on a click, chains a status line you already have, keeps the other keys of your entry, and puts the entry back exactly when you remove it.
- The transcript reader works on read(2) and memchr, so a full pass over several gigabytes of transcripts stays near 50 MB of memory.
- The process figures use the Mach timebase, so CPU percentages are right on every Mac.
- The popover renders only when something changed, and the token totals are rebuilt only when a transcript moved or the day turned.
- No network code, no account, no analytics.
