import XCTest
@testable import Browser

final class ContentBlockerTests: XCTestCase {
    func testBlockRuleShape() throws {
        let json = ContentBlocker.rulesJSON(domains: ["doubleclick.net"], allowlist: [])!
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed.count, 1)
        let trigger = parsed[0]["trigger"] as! [String: Any]
        XCTAssertEqual(trigger["url-filter"] as? String, "^https?://([^:/]+\\.)?doubleclick\\.net[:/]")
        XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
        let action = parsed[0]["action"] as! [String: Any]
        XCTAssertEqual(action["type"] as? String, "block")
    }

    func testAllowlistAppendsIgnoreRule() throws {
        let json = ContentBlocker.rulesJSON(domains: ["a.com"], allowlist: ["example.org"])!
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed.count, 2)
        let trigger = parsed[1]["trigger"] as! [String: Any]
        XCTAssertEqual(trigger["if-domain"] as? [String], ["*example.org"])
        let action = parsed[1]["action"] as! [String: Any]
        XCTAssertEqual(action["type"] as? String, "ignore-previous-rules")
    }

    func testRawRulesPassThrough() throws {
        let raw: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]]]
        let json = ContentBlocker.rulesJSON(domains: [], allowlist: [], rawRules: raw)!
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual((parsed[0]["action"] as? [String: Any])?["type"] as? String, "block-cookies")
    }

    func testLoadBlocklistFallsBackToDefaults() {
        let list = ContentBlocker.loadBlocklist(from: URL(fileURLWithPath: "/nonexistent/blocklist.json"))
        XCTAssertEqual(list.domains, ContentBlocker.defaultDomains)
        XCTAssertTrue(list.allowlist.isEmpty)
    }

    func testLoadBlocklistReadsFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("blocklist.json")
        try #"{"domains": ["x.com"], "allowlist": ["y.org"]}"#.write(to: url, atomically: true, encoding: .utf8)
        let list = ContentBlocker.loadBlocklist(from: url)
        XCTAssertEqual(list.domains, ["x.com"])
        XCTAssertEqual(list.allowlist, ["y.org"])
    }
}

final class ClosedTabStackTests: XCTestCase {
    func record(_ title: String) -> ClosedTab {
        ClosedTab(url: URL(string: "https://example.com"), title: title, pinned: false, workspaceID: UUID())
    }

    func testPopIsLIFO() {
        var stack = ClosedTabStack()
        stack.push(record("first"))
        stack.push(record("second"))
        XCTAssertEqual(stack.pop()?.title, "second")
        XCTAssertEqual(stack.pop()?.title, "first")
        XCTAssertNil(stack.pop())
    }

    func testBoundedAtLimit() {
        var stack = ClosedTabStack()
        for i in 0..<(ClosedTabStack.limit + 10) {
            stack.push(record("t\(i)"))
        }
        XCTAssertEqual(stack.records.count, ClosedTabStack.limit)
        XCTAssertEqual(stack.pop()?.title, "t\(ClosedTabStack.limit + 9)")
        XCTAssertEqual(stack.records.first?.title, "t10")
    }
}

final class SiteZoomTests: XCTestCase {
    func makePath() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test.sqlite").path
    }

    func testZoomRoundTrip() throws {
        let store = try DataStore(path: try makePath())
        store.setZoom(1.5, host: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 1.5)
        XCTAssertNil(store.zoom(forHost: "other.com"))
    }

    func testZoomOfOneDeletesRow() throws {
        let store = try DataStore(path: try makePath())
        store.setZoom(1.5, host: "example.com")
        store.setZoom(1.0, host: "example.com")
        XCTAssertNil(store.zoom(forHost: "example.com"))
    }

    func testReopenKeepsZoom() throws {
        let path = try makePath()
        var store: DataStore? = try DataStore(path: path)
        store?.setZoom(0.8, host: "example.com")
        store = nil
        store = try DataStore(path: path)
        XCTAssertEqual(store?.zoom(forHost: "example.com"), 0.8)
    }
}

final class ErrorPageTests: XCTestCase {
    func testEscapesHTML() {
        let html = ErrorPage.html(message: "<b>bad & wrong</b>", url: "https://x.dev/?q=\"a\"")
        XCTAssertTrue(html.contains("&lt;b&gt;bad &amp; wrong&lt;/b&gt;"))
        XCTAssertTrue(html.contains("https://x.dev/?q=&quot;a&quot;"))
        XCTAssertFalse(html.contains("<b>bad"))
    }
}

final class FaviconFilenameTests: XCTestCase {
    func testKeepsSafeHostCharacters() {
        XCTAssertEqual(FaviconStore.filename(for: "sub.example-1.com"), "sub.example-1.com.ico")
    }

    func testReplacesUnsafeCharacters() {
        XCTAssertEqual(FaviconStore.filename(for: "A/b:c"), "a_b_c.ico")
    }
}

final class DownloadNameTests: XCTestCase {
    func testDeduplicatesFilenames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(WebViewStore.availableURL(for: "a.txt", in: dir).lastPathComponent, "a.txt")
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WebViewStore.availableURL(for: "a.txt", in: dir).lastPathComponent, "a (2).txt")
        try "x".write(to: dir.appendingPathComponent("a (2).txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WebViewStore.availableURL(for: "a.txt", in: dir).lastPathComponent, "a (3).txt")
    }
}

final class ContainerSessionTests: XCTestCase {
    func testContainerIDRoundTrips() {
        var ws = Workspace(name: "Work")
        let tab = Tab(url: URL(string: "https://a.com"), title: "A")
        ws.tabs = [tab]
        ws.activeTabID = tab.id
        let snapshot = SessionSnapshot.capture(workspaces: [ws], activeWorkspaceID: ws.id)
        XCTAssertEqual(snapshot.workspaces[0].containerID, ws.containerID.uuidString)
        let (restored, _) = snapshot.restore()
        XCTAssertEqual(restored[0].containerID, ws.containerID)
    }

    func testOldSnapshotWithoutContainerGetsFreshOne() throws {
        let json = ##"{"schemaVersion": 1, "activeWorkspaceIndex": 0, "workspaces": [{"name": "Home", "color": "#fff", "tabs": [], "activeTabIndex": null}]}"##
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        let (restored, _) = snapshot.restore()
        XCTAssertEqual(restored.count, 1)
        XCTAssertNotNil(restored[0].containerID)
    }
}

final class ConfigDailyDriverTests: XCTestCase {
    func testNewSectionsDefault() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(config.privacy.blockTrackers)
        XCTAssertTrue(config.privacy.allowlist.isEmpty)
        XCTAssertEqual(config.tabs.maxLiveWebviews, 12)
        XCTAssertEqual(config.downloads.directory, "~/Downloads")
    }

    func testWebviewCapClamps() throws {
        let json = #"{"tabs": {"maxLiveWebviews": 1}, "privacy": {"blockTrackers": false, "allowlist": ["a.dev"]}}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.tabs.maxLiveWebviews, 2)
        XCTAssertFalse(config.privacy.blockTrackers)
        XCTAssertEqual(config.privacy.allowlist, ["a.dev"])
    }

    func testDownloadsDirectoryExpandsTilde() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(config.downloads.resolvedURL.path.contains("~"))
        XCTAssertTrue(config.downloads.resolvedURL.path.hasSuffix("/Downloads"))
    }
}
