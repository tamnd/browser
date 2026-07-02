import Foundation

struct SearchEngine: Codable, Equatable {
    var id: String
    var name: String
    var url: String
    var keyword: String?

    func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        return URL(string: url.replacingOccurrences(of: "%s", with: encoded))
    }
}

struct AppSection: Codable, Equatable {
    var restoreSession: Bool = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restoreSession = try c.decodeIfPresent(Bool.self, forKey: .restoreSession) ?? true
    }
}

struct AppearanceSection: Codable, Equatable {
    var theme: String = "graphite"
    var variant: String = "auto"
    var fontScale: Double = 1.0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "graphite"
        variant = try c.decodeIfPresent(String.self, forKey: .variant) ?? "auto"
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
    }
}

struct LayoutSection: Codable, Equatable {
    var sidebarVisible: Bool = true
    var sidebarWidth: Double = 240
    var paneMax: Int = 3

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 240
        paneMax = min(max(try c.decodeIfPresent(Int.self, forKey: .paneMax) ?? 3, 1), 3)
    }
}

struct SearchSection: Codable, Equatable {
    var defaultEngine: String = "duckduckgo"
    var engines: [SearchEngine] = SearchSection.builtinEngines

    static let builtinEngines: [SearchEngine] = [
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s", keyword: "d"),
        SearchEngine(id: "google", name: "Google", url: "https://www.google.com/search?q=%s", keyword: "g"),
        SearchEngine(id: "kagi", name: "Kagi", url: "https://kagi.com/search?q=%s", keyword: "k"),
        SearchEngine(id: "brave", name: "Brave Search", url: "https://search.brave.com/search?q=%s", keyword: "b"),
    ]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultEngine = try c.decodeIfPresent(String.self, forKey: .defaultEngine) ?? "duckduckgo"
        let user = try c.decodeIfPresent([SearchEngine].self, forKey: .engines) ?? []
        var merged = SearchSection.builtinEngines
        for engine in user {
            if let i = merged.firstIndex(where: { $0.id == engine.id }) {
                merged[i] = engine
            } else {
                merged.append(engine)
            }
        }
        engines = merged
    }

    var resolvedDefault: SearchEngine {
        engines.first { $0.id == defaultEngine } ?? SearchSection.builtinEngines[0]
    }

    func engine(keyword: String) -> SearchEngine? {
        engines.first { $0.keyword == keyword }
    }
}

struct PluginsSection: Codable, Equatable {
    var enabled: [String] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent([String].self, forKey: .enabled) ?? []
    }
}

struct AppConfig: Codable, Equatable {
    var configVersion: Int = 1
    var app = AppSection()
    var appearance = AppearanceSection()
    var layout = LayoutSection()
    var search = SearchSection()
    var plugins = PluginsSection()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configVersion = try c.decodeIfPresent(Int.self, forKey: .configVersion) ?? 1
        app = try c.decodeIfPresent(AppSection.self, forKey: .app) ?? AppSection()
        appearance = try c.decodeIfPresent(AppearanceSection.self, forKey: .appearance) ?? AppearanceSection()
        layout = try c.decodeIfPresent(LayoutSection.self, forKey: .layout) ?? LayoutSection()
        search = try c.decodeIfPresent(SearchSection.self, forKey: .search) ?? SearchSection()
        plugins = try c.decodeIfPresent(PluginsSection.self, forKey: .plugins) ?? PluginsSection()
    }

    static func load(from url: URL) -> (config: AppConfig, warnings: [String]) {
        guard let data = try? Data(contentsOf: url) else {
            return (AppConfig(), [])
        }
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return (config, [])
        } catch {
            return (AppConfig(), ["config.json: \(error.localizedDescription), using defaults"])
        }
    }
}
