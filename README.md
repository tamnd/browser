# browser

A lean, keyboard-first web browser for macOS where every surface is customizable through plain files.
Think Obsidian, for the web: your browser is a folder of JSON, CSS, and JS that you own.

The engine is the system WebKit (WKWebView).
The shell is native Swift and SwiftUI, a plain SwiftPM executable with no Xcode project.
There is no telemetry and nothing leaves your machine without an explicit action.

## What it does today (v0.1.2)

- Workspaces with a vertical tab sidebar, tabs nest under the tab that opened them
- Each workspace is a container with its own cookies and storage
- Split view, up to three panes side by side
- One palette for everything: cmd+l for URLs, history, and search, `>` for commands, `#` to jump to any tab in any workspace
- Every keybinding remappable in `keymap.json`, including multi-key sequences like `"g t"`
- Tracker blocking driven by `blocklist.json`, with allowlist and per-site toggle
- Downloads with progress in the sidebar, deduped names in your downloads folder
- Find in page (cmd+f), reopen closed tab (cmd+shift+t), per-site zoom that sticks
- Favicons cached in the profile, readable error pages on failed loads
- Themes as JSON design tokens, hot-reloaded on save
- CSS snippets injected into pages, Obsidian style
- JS plugins on JavaScriptCore: commands, tabs, events, dynamic page styles, per-plugin storage, suggested keybindings
- Plugin dev mode: save a file in a plugin folder and it reloads live
- History and sessions in SQLite, session restores on launch
- Memory stays bounded: only the most recent webviews stay live (`tabs.maxLiveWebviews`)

## The profile folder

Everything lives in `~/Library/Application Support/Browser` (override with `BROWSER_HOME`):

```
config.json      settings, hand-editable, hot-reloaded
keymap.json      chord or sequence -> command id, null unbinds a default
blocklist.json   tracker domains, allowlist, raw WebKit content rules
themes/          each theme is a folder with theme.json
snippets/        *.css injected into every page
plugins/         each plugin is a folder with manifest.json + main.js
favicons/        icon cache, safe to delete
data.sqlite      history, per-site zoom, and sessions
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

Early but daily drivable.
v0.1.0 was the skeleton, v0.1.1 added containers, blocking, downloads, and find, v0.1.2 unified the palette and grew the plugin API.
Internal pages, browser.fetch with permissions, and reader mode are next.
Releases bump the patch number.

## License

MIT
