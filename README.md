# browser

A lean, keyboard-first web browser for macOS where every surface is customizable through plain files.
Think Obsidian, for the web: your browser is a folder of JSON, CSS, and JS that you own.

The engine is the system WebKit (WKWebView).
The shell is native Swift and SwiftUI, a plain SwiftPM executable with no Xcode project.
There is no telemetry and nothing leaves your machine without an explicit action.

## What it does today (v0.1)

- Workspaces with a vertical tab sidebar, tabs nest under the tab that opened them
- Split view, up to three panes side by side
- Omnibox as a summonable palette (cmd+l): URLs, history suggestions, search, engine keywords
- Command palette (cmd+k) with fuzzy matching over every command
- Every keybinding remappable in `keymap.json`
- Themes as JSON design tokens, hot-reloaded on save
- CSS snippets injected into pages, Obsidian style
- JS plugins on JavaScriptCore: register commands, open tabs, notify, per-plugin storage
- History and sessions in SQLite, session restores on launch

## The profile folder

Everything lives in `~/Library/Application Support/Browser` (override with `BROWSER_HOME`):

```
config.json      settings, hand-editable, hot-reloaded
keymap.json      chord -> command id, null unbinds a default
themes/          each theme is a folder with theme.json
snippets/        *.css injected into every page
plugins/         each plugin is a folder with manifest.json + main.js
data.sqlite      history and sessions
```

Put the folder in git, sync it with anything, share it.
The database stays out via the `.gitignore` the app writes for you.

## Build

```
swift build
swift run Browser
```

Requires macOS 14+ and a recent Xcode toolchain.
To hack on it in Xcode, `open Package.swift`.

## Status

Early. v0.1 is the skeleton that browses.
Containers per workspace, content blocking, downloads, find in page, and the full plugin API are next.

## License

MIT
