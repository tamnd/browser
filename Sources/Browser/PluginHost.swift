import Foundation
import JavaScriptCore

struct PluginManifest: Codable, Equatable {
    var id: String
    var name: String
    var version: String
}

// v0.1 plugin host: one JSContext per plugin, everything on the main thread.
// API surface: browser.commands.register, browser.ui.notify,
// browser.tabs.open/list/active, browser.storage.get/set.
@MainActor
final class PluginHost {
    private weak var model: AppModel?
    private var contexts: [String: JSContext] = [:]
    private(set) var loaded: [PluginManifest] = []
    private(set) var errors: [String] = []

    init(model: AppModel) {
        self.model = model
    }

    func loadEnabled() {
        guard let model else { return }
        for id in model.config.plugins.enabled {
            load(id: id)
        }
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
        if let onload = context.objectForKeyedSubscript("onload"), !onload.isUndefined {
            onload.call(withArguments: [])
        }
    }

    func unloadAll() {
        for (id, context) in contexts {
            if let onunload = context.objectForKeyedSubscript("onunload"), !onunload.isUndefined {
                onunload.call(withArguments: [])
            }
            model?.commands.unregister(source: "plugin:\(id)")
        }
        contexts.removeAll()
        loaded.removeAll()
    }

    private func install(api context: JSContext, pluginID: String) {
        let browser = JSValue(newObjectIn: context)!
        let commands = JSValue(newObjectIn: context)!
        let tabs = JSValue(newObjectIn: context)!
        let ui = JSValue(newObjectIn: context)!
        let storage = JSValue(newObjectIn: context)!

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

        browser.setObject(commands, forKeyedSubscript: "commands" as NSString)
        browser.setObject(tabs, forKeyedSubscript: "tabs" as NSString)
        browser.setObject(ui, forKeyedSubscript: "ui" as NSString)
        browser.setObject(storage, forKeyedSubscript: "storage" as NSString)
        browser.setObject("0.1.0", forKeyedSubscript: "version" as NSString)
        context.setObject(browser, forKeyedSubscript: "browser" as NSString)
    }
}
