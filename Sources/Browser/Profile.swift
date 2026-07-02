import Foundation

enum Profile {
    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["BROWSER_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Browser", isDirectory: true)
    }

    static var configURL: URL { baseURL.appendingPathComponent("config.json") }
    static var keymapURL: URL { baseURL.appendingPathComponent("keymap.json") }
    static var blocklistURL: URL { baseURL.appendingPathComponent("blocklist.json") }
    static var themesURL: URL { baseURL.appendingPathComponent("themes", isDirectory: true) }
    static var snippetsURL: URL { baseURL.appendingPathComponent("snippets", isDirectory: true) }
    static var pluginsURL: URL { baseURL.appendingPathComponent("plugins", isDirectory: true) }
    static var faviconsURL: URL { baseURL.appendingPathComponent("favicons", isDirectory: true) }
    static var databasePath: String { baseURL.appendingPathComponent("data.sqlite").path }

    static func ensureScaffold() throws {
        let fm = FileManager.default
        for dir in [baseURL, themesURL, snippetsURL, pluginsURL, faviconsURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try writeIfMissing(configURL, defaultConfigJSON)
        try writeIfMissing(blocklistURL, defaultBlocklistJSON)
        try writeIfMissing(keymapURL, "{\n  \"_help\": \"chord -> command id, null unbinds a default, see README.md\"\n}\n")
        let graphite = themesURL.appendingPathComponent("graphite", isDirectory: true)
        try fm.createDirectory(at: graphite, withIntermediateDirectories: true)
        try writeIfMissing(graphite.appendingPathComponent("theme.json"), defaultThemeJSON)
        try writeIfMissing(snippetsURL.appendingPathComponent("example.css"), "/* Every .css file in this folder is injected into every page. */\n/* Delete or edit freely; changes apply to new page loads. */\n")
        try writeIfMissing(baseURL.appendingPathComponent("README.md"), profileReadme)
        try writeIfMissing(baseURL.appendingPathComponent(".gitignore"), "data.sqlite\ndata.sqlite-wal\ndata.sqlite-shm\n")
    }

    private static func writeIfMissing(_ url: URL, _ content: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static let defaultConfigJSON = """
    {
      "configVersion": 1,
      "app": {
        "restoreSession": true
      },
      "appearance": {
        "theme": "graphite",
        "variant": "auto",
        "fontScale": 1.0
      },
      "layout": {
        "sidebarVisible": true,
        "sidebarWidth": 240,
        "paneMax": 3
      },
      "search": {
        "defaultEngine": "duckduckgo",
        "engines": []
      },
      "privacy": {
        "blockTrackers": true,
        "allowlist": []
      },
      "tabs": {
        "maxLiveWebviews": 12
      },
      "downloads": {
        "directory": "~/Downloads"
      },
      "plugins": {
        "enabled": []
      }
    }
    """

    static var defaultBlocklistJSON: String {
        let domains = ContentBlocker.defaultDomains.map { "    \"\($0)\"" }.joined(separator: ",\n")
        return """
        {
          "_help": "domains are blocked as third-party loads; allowlist turns blocking off on those sites; rules holds raw WebKit content rules",
          "domains": [
        \(domains)
          ],
          "allowlist": [],
          "rules": []
        }
        """
    }

    static let defaultThemeJSON = """
    {
      "name": "graphite",
      "variants": {
        "dark": {},
        "light": {}
      }
    }
    """

    static let profileReadme = """
    # Your browser profile

    This folder is the whole configuration surface of the browser.
    Every file is plain text, safe to edit by hand, and picked up while the app runs.

    - `config.json` is the settings file. The app rewrites it only when you change settings from inside the app.
    - `keymap.json` maps key chords to command ids, like `"cmd+shift+x": "tab.close"`. Use `null` to unbind a default.
    - `blocklist.json` drives the tracker blocker: domains to block, sites to allowlist, and raw WebKit content rules.
    - `themes/<name>/theme.json` holds design tokens for the chrome, with `light` and `dark` variants.
    - `snippets/*.css` are injected into every page you visit, in alphabetical order.
    - `plugins/<id>/` holds a plugin: a `manifest.json` and a `main.js`. Enable ids in `config.json` under `plugins.enabled`.
    - `favicons/` is the icon cache. Safe to delete, it refills as you browse.
    - `data.sqlite` is history, per-site zoom, and session state. It belongs to the app, leave it alone.

    This folder is yours: put it in git, sync it, share it.
    The `.gitignore` here already keeps the database out.
    """
}
