# Contributing

Issues are welcome: bugs, wrong figures, ideas. A screenshot of the popover and your macOS version help most.

Pull requests are welcome too. Keep them small, one change each, and run `swift build`, `swiftlint lint --strict` and the tests before you open one (the README has the test command). A change in behaviour comes with a test for it.

The app keeps a few rules, and a change that needs to break one will not be merged:

- No network calls of any kind. No analytics, no update check, no price fetch.
- Plan figures come only from Claude Code's documented status line feed. No Keychain, no token, no private endpoint.
- Transcripts are read for the fields the privacy page names and nothing else; `memory/` and `tool-results/` are never opened.
- `settings.json` is touched only on a click, and only its `statusLine` key changes.
- Cost is labelled list price equivalent, never spent.
- No em dash, en dash, middle dot or pipe in the UI or the docs.
