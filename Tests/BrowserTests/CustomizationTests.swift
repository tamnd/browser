import XCTest
@testable import Browser

final class KeySequenceTests: XCTestCase {
    func testParsesMultiChordSequence() {
        let seq = KeySequence.parse("g t")
        XCTAssertEqual(seq?.chords.count, 2)
        XCTAssertEqual(seq?.chords[0].key, "g")
        XCTAssertEqual(seq?.chords[1].key, "t")
        XCTAssertEqual(seq?.description, "g t")
    }

    func testParsesSingleChord() {
        let seq = KeySequence.parse("cmd+shift+k")
        XCTAssertEqual(seq?.chords, [KeyChord.parse("cmd+shift+k")!])
    }

    func testRejectsBadChordInSequence() {
        XCTAssertNil(KeySequence.parse("g bogus+key"))
        XCTAssertNil(KeySequence.parse("  "))
    }
}

final class SequenceKeymapTests: XCTestCase {
    func testSequenceMatching() {
        let keymap = Keymap(user: ["g t": "tab.next"])
        XCTAssertEqual(keymap.match([KeyChord.parse("g")!]), .prefix)
        XCTAssertEqual(keymap.match([KeyChord.parse("g")!, KeyChord.parse("t")!]), .command("tab.next"))
        XCTAssertEqual(keymap.match([KeyChord.parse("g")!, KeyChord.parse("x")!]), .none)
    }

    func testSingleChordStillMatches() {
        let keymap = Keymap()
        XCTAssertEqual(keymap.match([KeyChord.parse("cmd+t")!]), .command("tab.new"))
    }

    func testPrefixConflictWarns() {
        let keymap = Keymap(user: ["g": "nav.back", "g t": "tab.next"])
        XCTAssertTrue(keymap.warnings.contains { $0.contains("hides the longer binding") })
    }

    func testSuggestedLayersUnderUser() {
        let suggested = ["cmd+shift+h": "hello.greet", "cmd+t": "hello.greet"]
        let keymap = Keymap(user: ["cmd+t": "tab.new", "cmd+shift+h": nil], suggested: suggested)
        XCTAssertEqual(keymap.command(for: KeyChord.parse("cmd+t")!), "tab.new")
        XCTAssertNil(keymap.command(for: KeyChord.parse("cmd+shift+h")!))
    }

    func testSuggestedOverridesDefaults() {
        let keymap = Keymap(suggested: ["cmd+t": "hello.greet"])
        XCTAssertEqual(keymap.command(for: KeyChord.parse("cmd+t")!), "hello.greet")
    }

    func testSequenceLookupForCommand() {
        let keymap = Keymap(user: ["g t": "my.command"])
        XCTAssertEqual(keymap.sequence(for: "my.command")?.description, "g t")
    }
}

final class PaletteModeTests: XCTestCase {
    func testCommandPrefix() {
        let (mode, query) = PaletteMode.parse("> reload page")
        XCTAssertEqual(mode, .command)
        XCTAssertEqual(query, "reload page")
    }

    func testTabPrefix() {
        let (mode, query) = PaletteMode.parse("#docs")
        XCTAssertEqual(mode, .tabs)
        XCTAssertEqual(query, "docs")
    }

    func testBareTextNavigates() {
        let (mode, query) = PaletteMode.parse("  example.com ")
        XCTAssertEqual(mode, .navigate)
        XCTAssertEqual(query, "example.com")
    }

    func testPrefixOnlyGivesEmptyQuery() {
        XCTAssertEqual(PaletteMode.parse(">").query, "")
        XCTAssertEqual(PaletteMode.parse("#").query, "")
    }
}

final class ManifestValidationTests: XCTestCase {
    func testUnknownPermissionRejected() {
        let manifest = PluginManifest(id: "x", name: "X", version: "1.0.0", permissions: ["teleport"])
        XCTAssertEqual(manifest.validate(appVersion: "0.1.2"), "unknown permission \"teleport\"")
    }

    func testMinAppVersionRejected() {
        let manifest = PluginManifest(id: "x", name: "X", version: "1.0.0", minAppVersion: "9.9.9")
        XCTAssertNotNil(manifest.validate(appVersion: "0.1.2"))
    }

    func testValidManifestPasses() {
        let manifest = PluginManifest(id: "x", name: "X", version: "1.0.0", minAppVersion: "0.1.0")
        XCTAssertNil(manifest.validate(appVersion: "0.1.2"))
    }

    func testDecodesV1Fields() throws {
        let json = #"{"id": "a", "name": "A", "version": "1.0", "minAppVersion": "0.1.2", "suggestedKeymap": {"g a": "a.run"}}"#
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.minAppVersion, "0.1.2")
        XCTAssertEqual(manifest.suggestedKeymap?["g a"], "a.run")
    }

    func testOldManifestStillDecodes() throws {
        let json = #"{"id": "a", "name": "A", "version": "1.0"}"#
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        XCTAssertNil(manifest.minAppVersion)
        XCTAssertNil(manifest.validate(appVersion: "0.1.2"))
    }
}

final class SemverTests: XCTestCase {
    func testCompare() {
        XCTAssertEqual(Semver.compare("0.1.2", "0.1.2"), 0)
        XCTAssertEqual(Semver.compare("0.1.2", "0.1.10"), -1)
        XCTAssertEqual(Semver.compare("1.0", "0.9.9"), 1)
        XCTAssertEqual(Semver.compare("0.1", "0.1.0"), 0)
    }
}

final class StyleHostFilterTests: XCTestCase {
    func testHostListLandsInScript() {
        let js = UserStyles.injectionJS(css: "body{}", hosts: ["example.com"])
        XCTAssertTrue(js.contains("[\"example.com\"]"))
        XCTAssertTrue(js.contains("location.host"))
    }

    func testNoHostsMeansEmptyArray() {
        let js = UserStyles.injectionJS(css: "body{}")
        XCTAssertTrue(js.contains("var hosts = [];"))
    }
}
