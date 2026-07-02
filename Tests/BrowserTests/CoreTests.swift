import XCTest
@testable import Browser

final class FuzzyMatchTests: XCTestCase {
    func testExactPrefixBeatsScattered() {
        let a = FuzzyMatch.score(query: "tab", target: "Tab: New Tab")!
        let b = FuzzyMatch.score(query: "tab", target: "Toggle sidebar and browse")!
        XCTAssertGreaterThan(a, b)
    }

    func testNonSubsequenceIsNil() {
        XCTAssertNil(FuzzyMatch.score(query: "xyz", target: "tab.new"))
        XCTAssertNil(FuzzyMatch.score(query: "abc", target: "ab"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertEqual(FuzzyMatch.score(query: "", target: "anything"), 0)
    }

    func testWordBoundaryBonus() {
        let boundary = FuzzyMatch.score(query: "nt", target: "new tab")!
        let middle = FuzzyMatch.score(query: "nt", target: "aanaata")!
        XCTAssertGreaterThan(boundary, middle)
    }
}

final class KeymapTests: XCTestCase {
    func testParseBasicChord() {
        let chord = KeyChord.parse("cmd+shift+t")
        XCTAssertNotNil(chord)
        XCTAssertTrue(chord!.cmd)
        XCTAssertTrue(chord!.shift)
        XCTAssertFalse(chord!.ctrl)
        XCTAssertEqual(chord!.key, "t")
    }

    func testParseAliases() {
        XCTAssertEqual(KeyChord.parse("cmd+esc")?.key, "escape")
        XCTAssertEqual(KeyChord.parse("cmd+return")?.key, "enter")
        XCTAssertEqual(KeyChord.parse("option+x")?.alt, true)
    }

    func testShiftedSymbolNormalizes() {
        XCTAssertEqual(KeyChord.parse("cmd+shift+{")?.key, "[")
    }

    func testInvalidChords() {
        XCTAssertNil(KeyChord.parse(""))
        XCTAssertNil(KeyChord.parse("cmd+"))
        XCTAssertNil(KeyChord.parse("cmd+bogus"))
        XCTAssertNil(KeyChord.parse("cmd"))
    }

    func testDefaultsResolve() {
        let keymap = Keymap()
        XCTAssertEqual(keymap.command(for: KeyChord.parse("cmd+t")!), "tab.new")
        XCTAssertEqual(keymap.command(for: KeyChord.parse("cmd+l")!), "omnibox.open")
    }

    func testUserOverrideAndUnbind() {
        let keymap = Keymap(user: ["cmd+t": "workspace.new", "cmd+w": nil])
        XCTAssertEqual(keymap.command(for: KeyChord.parse("cmd+t")!), "workspace.new")
        XCTAssertNil(keymap.command(for: KeyChord.parse("cmd+w")!))
    }

    func testBadUserChordWarns() {
        let keymap = Keymap(user: ["cmd+bogus": "tab.new"])
        XCTAssertEqual(keymap.warnings.count, 1)
    }
}

final class OmniboxClassifierTests: XCTestCase {
    let search = SearchSection()

    func url(_ input: String) -> String? {
        guard let action = OmniboxClassifier.classify(input, search: search) else { return nil }
        return OmniboxClassifier.url(for: action)?.absoluteString
    }

    func testExplicitScheme() {
        XCTAssertEqual(url("https://example.com/a?b=c"), "https://example.com/a?b=c")
    }

    func testLocalhostAndIP() {
        XCTAssertEqual(url("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(url("192.168.1.1/admin"), "http://192.168.1.1/admin")
    }

    func testDotHeuristic() {
        XCTAssertEqual(url("example.com"), "https://example.com")
        XCTAssertEqual(url("news.ycombinator.com/item?id=1"), "https://news.ycombinator.com/item?id=1")
    }

    func testNumbersAreSearch() {
        XCTAssertTrue(url("3.14")!.contains("duckduckgo.com"))
    }

    func testPlainQueryIsSearch() {
        XCTAssertTrue(url("how to exit vim")!.contains("duckduckgo.com"))
    }

    func testSpacedDotIsSearch() {
        XCTAssertTrue(url("how to 2.0")!.contains("duckduckgo.com"))
    }

    func testEngineKeyword() {
        guard case .search(let engine, let query)? = OmniboxClassifier.classify("g rust wkwebview", search: search) else {
            return XCTFail("expected search")
        }
        XCTAssertEqual(engine.id, "google")
        XCTAssertEqual(query, "rust wkwebview")
    }

    func testEmptyIsNil() {
        XCTAssertNil(OmniboxClassifier.classify("   ", search: search))
    }
}

final class ThemeTests: XCTestCase {
    func testHexParsing() {
        let full = Theme.hexComponents("#ff8000")
        XCTAssertNotNil(full)
        XCTAssertEqual(full!.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(full!.g, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(full!.b, 0, accuracy: 0.001)
        XCTAssertEqual(full!.a, 1.0, accuracy: 0.001)

        let short = Theme.hexComponents("#fff")
        XCTAssertEqual(short!.r, 1.0, accuracy: 0.001)

        let alpha = Theme.hexComponents("#00000080")
        XCTAssertEqual(alpha!.a, 128.0 / 255.0, accuracy: 0.01)

        XCTAssertNil(Theme.hexComponents("fff"))
        XCTAssertNil(Theme.hexComponents("#zzz"))
    }

    func testTokenFallback() {
        let theme = Theme(name: "t", light: ["accent": "#111111"], dark: [:])
        XCTAssertEqual(theme.token("accent", dark: false), "#111111")
        XCTAssertEqual(theme.token("accent", dark: true), Theme.defaultDark["accent"])
        XCTAssertEqual(theme.token("bg.base", dark: false), Theme.defaultLight["bg.base"])
    }
}

final class ConfigTests: XCTestCase {
    func testPartialConfigKeepsDefaults() throws {
        let json = #"{"appearance": {"theme": "paper"}, "layout": {"paneMax": 9}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.appearance.theme, "paper")
        XCTAssertEqual(config.appearance.variant, "auto")
        XCTAssertEqual(config.layout.paneMax, 3)
        XCTAssertEqual(config.search.defaultEngine, "duckduckgo")
        XCTAssertTrue(config.app.restoreSession)
    }

    func testUserEngineOverridesBuiltin() throws {
        let json = #"{"search": {"defaultEngine": "kagi", "engines": [{"id": "kagi", "name": "Kagi", "url": "https://kagi.com/search?q=%s", "keyword": "kg"}]}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.search.resolvedDefault.id, "kagi")
        XCTAssertEqual(config.search.engine(keyword: "kg")?.id, "kagi")
        XCTAssertNotNil(config.search.engine(keyword: "g"))
    }

    func testBrokenConfigFallsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        try "{not json".write(to: url, atomically: true, encoding: .utf8)
        let (config, warnings) = AppConfig.load(from: url)
        XCTAssertEqual(config, AppConfig())
        XCTAssertEqual(warnings.count, 1)
    }
}

final class DataStoreTests: XCTestCase {
    func makeStore() throws -> DataStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try DataStore(path: dir.appendingPathComponent("test.sqlite").path)
    }

    func testRecordAndSuggest() throws {
        let store = try makeStore()
        store.recordVisit(url: "https://example.com", title: "Example Domain")
        store.recordVisit(url: "https://example.com", title: "Example Domain")
        store.recordVisit(url: "https://swift.org", title: "Swift")

        let byTitle = store.suggest("example")
        XCTAssertEqual(byTitle.count, 1)
        XCTAssertEqual(byTitle[0].visitCount, 2)

        let byURL = store.suggest("swift.org")
        XCTAssertEqual(byURL.count, 1)
        XCTAssertEqual(byURL[0].title, "Swift")
    }

    func testFrequencyOrdersSuggestions() throws {
        let store = try makeStore()
        store.recordVisit(url: "https://a.dev/page", title: "alpha")
        for _ in 0..<5 {
            store.recordVisit(url: "https://b.dev/page", title: "beta")
        }
        let results = store.suggest(".dev")
        XCTAssertEqual(results.first?.title, "beta")
    }

    func testLikeEscaping() throws {
        let store = try makeStore()
        store.recordVisit(url: "https://example.com/100%25", title: "percent")
        XCTAssertEqual(store.suggest("100%").count, 1)
        XCTAssertEqual(store.suggest("zzz").count, 0)
    }

    func testSessionRoundTrip() throws {
        let store = try makeStore()
        var workspace = Workspace(name: "Work", color: "#123456")
        let parent = Tab(url: URL(string: "https://a.com"), title: "A")
        let child = Tab(url: URL(string: "https://b.com"), title: "B", parentID: parent.id)
        workspace.tabs = [parent, child]
        workspace.activeTabID = child.id
        workspace.paneTabIDs = [child.id]

        let snapshot = SessionSnapshot.capture(workspaces: [workspace], activeWorkspaceID: workspace.id)
        store.saveSession(snapshot)
        let loaded = store.loadSession()
        XCTAssertEqual(loaded, snapshot)

        let (restored, activeIndex) = loaded!.restore()
        XCTAssertEqual(activeIndex, 0)
        XCTAssertEqual(restored[0].tabs.count, 2)
        XCTAssertEqual(restored[0].tabs[1].parentID, restored[0].tabs[0].id)
        XCTAssertEqual(restored[0].activeTabID, restored[0].tabs[1].id)
    }

    func testLoadSessionEmptyIsNil() throws {
        let store = try makeStore()
        XCTAssertNil(store.loadSession())
    }
}

final class ModelTests: XCTestCase {
    func testDisplayRowsNestChildren() {
        var ws = Workspace(name: "t")
        let root = Tab(title: "root")
        let child = Tab(title: "child", parentID: root.id)
        let grandchild = Tab(title: "grandchild", parentID: child.id)
        let pinned = Tab(title: "pinned", pinned: true)
        let other = Tab(title: "other")
        ws.tabs = [root, child, other, grandchild, pinned]

        let rows = ws.displayRows()
        XCTAssertEqual(rows.map { $0.tab.title }, ["pinned", "root", "child", "grandchild", "other"])
        XCTAssertEqual(rows.map { $0.depth }, [0, 0, 1, 2, 0])
    }

    func testDisplayRowsOrphanBecomesRoot() {
        var ws = Workspace(name: "t")
        let orphan = Tab(title: "orphan", parentID: UUID())
        ws.tabs = [orphan]
        let rows = ws.displayRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].depth, 0)
    }

    func testUserStylesInjectionEscapesCSS() {
        let js = UserStyles.injectionJS(css: "body { content: \"x\"; }\n/* `tick` */")
        XCTAssertTrue(js.contains("data-browser-snippet"))
        XCTAssertFalse(js.contains("content: \"x\"; }\n/*"))
    }
}
