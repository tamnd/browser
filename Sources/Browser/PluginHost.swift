import Foundation
import JavaScriptCore

struct PluginManifest: Codable, Equatable {
    var id: String
    var name: String
    var version: String
    var minAppVersion: String?
    var permissions: [String]?
    var suggestedKeymap: [String: String]?

    // No permissions exist yet; the first one ships with browser.fetch.
    // Rejecting unknown names now means old app versions fail loudly
    // instead of running a plugin without the guarantee it asked for.
    static let knownPermissions: Set<String> = []

    func validate(appVersion: String) -> String? {
        for permission in permissions ?? [] where !PluginManifest.knownPermissions.contains(permission) {
            return "unknown permission \"\(permission)\""
        }
        if let minAppVersion, Semver.compare(appVersion, minAppVersion) < 0 {
            return "needs app \(minAppVersion) or newer, this is \(appVersion)"
        }
        return nil
    }
}

enum Semver {
    // Plain numeric dotted compare, missing parts count as zero.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

// One JSContext per plugin, everything on the main thread.
// API surface: browser.commands, browser.tabs, browser.ui, browser.storage,
// browser.events, browser.styles.
@MainActor
final class PluginHost {
    static let appVersion = "0.1.2"

    private weak var model: AppModel?
    private var contexts: [String: JSContext] = [:]
    private var listeners: [String: [(pluginID: String, fn: JSValue)]] = [:]
    private(set) var loaded: [PluginManifest] = []
    private(set) var errors: [String] = []

    init(model: AppModel) {
        self.model = model
    }

    // Plugin manifest suggestions, layered under the user keymap.
    var suggestedKeys: [String: String] {
        var out: [String: String] = [:]
        for manifest in loaded {
            for (chord, command) in manifest.suggestedKeymap ?? [:] {
                out[chord] = command
            }
        }
        return out
    }

    func loadEnabled() {
        guard let model else { return }
        for id in model.config.plugins.enabled {
            load(id: id)
        }
    }

    func reloadEnabled() {
        guard let model else { return }
        for id in model.config.plugins.enabled {
            unload(id: id)
            load(id: id)
        }
        model.rebuildKeymap()
        model.banner = "plugins reloaded"
    }

    func reload(id: String) {
        unload(id: id)
        load(id: id)
        model?.rebuildKeymap()
        model?.banner = "plugin \(id) reloaded"
    }

    func load(id: String) {
        guard contexts[id] == nil else { return }
        let dir = Profile.pluginsURL.appendingPathComponent(id, isDirectory: true)
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let mainURL = dir.appendingPathComponent("main.js")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: manifestData),
              let source = try? String(contentsOf: mainURL, encoding: .utf8) else {
            errors.append("plugin \(id): missing or invalid manifest.json/main.js")
            return
        }
        if let problem = manifest.validate(appVersion: PluginHost.appVersion) {
            errors.append("plugin \(id): \(problem)")
            model?.banner = "plugin \(id): \(problem)"
            return
        }
        guard let context = JSContext() else { return }
        context.name = "plugin:\(id)"
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "unknown"
            DispatchQueue.main.async {
                self?.errors.append("plugin \(id): \(message)")
                self?.model?.banner = "plugin \(id): \(message)"
            }
        }
        install(api: context, pluginID: id)
        context.evaluateScript(source)
        contexts[id] = context
        loaded.append(manifest)
        model?.commands.register(Command(id: "plugin.reload.\(id)", title: "Reload Plugin: \(manifest.name)", category: "Plugin", source: "plugin:\(id)") { [weak self] in
            self?.reload(id: id)
        })
        if let onload = context.objectForKeyedSubscript("onload"), !onload.isUndefined {
            onload.call(withArguments: [])
        }
    }

    func unload(id: String) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        if let onunload = context.objectForKeyedSubscript("onunload"), !onunload.isUndefined {
            onunload.call(withArguments: [])
        }
        model?.commands.unregister(source: "plugin:\(id)")
        model?.webViews.removePluginStyles(pluginID: id)
        for name in listeners.keys {
            listeners[name]?.removeAll { $0.pluginID == id }
        }
        loaded.removeAll { $0.id == id }
    }

    func unloadAll() {
        for id in Array(contexts.keys) {
            unload(id: id)
        }
    }

    func emit(_ name: String, _ payload: [String: Any] = [:]) {
        for listener in listeners[name] ?? [] {
            listener.fn.call(withArguments: [payload])
        }
    }

    private func install(api context: JSContext, pluginID: String) {
        let browser = JSValue(newObjectIn: context)!
        let commands = JSValue(newObjectIn: context)!
        let tabs = JSValue(newObjectIn: context)!
        let ui = JSValue(newObjectIn: context)!
        let storage = JSValue(newObjectIn: context)!
        let events = JSValue(newObjectIn: context)!
        let styles = JSValue(newObjectIn: context)!

        let registerCommand: @convention(block) (String, String, JSValue) -> Void = { [weak self] id, title, fn in
            guard let model = self?.model else { return }
            model.commands.register(Command(id: id, title: title, category: "Plugin", source: "plugin:\(pluginID)") {
                fn.call(withArguments: [])
            })
        }
        commands.setObject(registerCommand, forKeyedSubscript: "register" as NSString)

        let openTab: @convention(block) (String) -> Void = { [weak self] urlString in
            guard let model = self?.model, let url = URL(string: urlString) else { return }
            let id = model.newTab(url: url)
            model.navigate(tabID: id, to: url)
        }
        tabs.setObject(openTab, forKeyedSubscript: "open" as NSString)

        let listTabs: @convention(block) () -> [[String: String]] = { [weak self] in
            guard let model = self?.model else { return [] }
            return model.activeWorkspace.tabs.map {
                ["id": $0.id.uuidString, "url": $0.url?.absoluteString ?? "", "title": $0.title]
            }
        }
        tabs.setObject(listTabs, forKeyedSubscript: "list" as NSString)

        let activeTab: @convention(block) () -> [String: String] = { [weak self] in
            guard let model = self?.model,
                  let id = model.activeWorkspace.activeTabID,
                  let tab = model.tab(id) else { return [:] }
            return ["id": tab.id.uuidString, "url": tab.url?.absoluteString ?? "", "title": tab.title]
        }
        tabs.setObject(activeTab, forKeyedSubscript: "active" as NSString)

        let notify: @convention(block) (String) -> Void = { [weak self] message in
            self?.model?.banner = message
        }
        ui.setObject(notify, forKeyedSubscript: "notify" as NSString)

        let dataURL = Profile.pluginsURL.appendingPathComponent(pluginID, isDirectory: true).appendingPathComponent("data.json")
        let storageGet: @convention(block) (String) -> Any? = { key in
            guard let data = try? Data(contentsOf: dataURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj[key]
        }
        storage.setObject(storageGet, forKeyedSubscript: "get" as NSString)

        let storageSet: @convention(block) (String, JSValue) -> Void = { key, value in
            var obj: [String: Any] = [:]
            if let data = try? Data(contentsOf: dataURL),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj = existing
            }
            obj[key] = value.toObject()
            if JSONSerialization.isValidJSONObject(obj),
               let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dataURL)
            }
        }
        storage.setObject(storageSet, forKeyedSubscript: "set" as NSString)

        let on: @convention(block) (String, JSValue) -> Void = { [weak self] name, fn in
            self?.listeners[name, default: []].append((pluginID, fn))
        }
        events.setObject(on, forKeyedSubscript: "on" as NSString)

        let styleRegister: @convention(block) (String, String, JSValue) -> Void = { [weak self] styleID, css, hosts in
            let hostList = hosts.isUndefined || hosts.isNull ? [] : (hosts.toArray() as? [String] ?? [])
            self?.model?.webViews.setPluginStyle(pluginID: pluginID, styleID: styleID, css: css, hosts: hostList)
        }
        styles.setObject(styleRegister, forKeyedSubscript: "register" as NSString)

        let styleUnregister: @convention(block) (String) -> Void = { [weak self] styleID in
            self?.model?.webViews.removePluginStyle(pluginID: pluginID, styleID: styleID)
        }
        styles.setObject(styleUnregister, forKeyedSubscript: "unregister" as NSString)

        browser.setObject(commands, forKeyedSubscript: "commands" as NSString)
        browser.setObject(tabs, forKeyedSubscript: "tabs" as NSString)
        browser.setObject(ui, forKeyedSubscript: "ui" as NSString)
        browser.setObject(storage, forKeyedSubscript: "storage" as NSString)
        browser.setObject(events, forKeyedSubscript: "events" as NSString)
        browser.setObject(styles, forKeyedSubscript: "styles" as NSString)
        browser.setObject(PluginHost.appVersion, forKeyedSubscript: "version" as NSString)
        context.setObject(browser, forKeyedSubscript: "browser" as NSString)
    }
}
