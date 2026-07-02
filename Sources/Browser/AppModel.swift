import AppKit
import Foundation
import SwiftUI
import WebKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceID = UUID()
    @Published var config = AppConfig()
    @Published var theme = Theme.builtin
    @Published var sidebarVisible = true
    @Published var banner: String?

    @Published var showOmnibox = false
    @Published var omniboxText = ""
    @Published var omniboxSuggestions: [OmniboxSuggestion] = []
    @Published var omniboxSelection = 0

    @Published var showPalette = false
    @Published var paletteText = ""
    @Published var paletteSelection = 0

    @Published var showFind = false
    @Published var findText = ""
    @Published var findMatched: Bool?

    @Published var downloads: [DownloadItem] = []

    let commands = CommandRegistry()
    let favicons = FaviconStore()
    private(set) var keymap = Keymap()
    private(set) var store: DataStore?
    lazy var webViews = WebViewStore(model: self)
    private(set) var pluginHost: PluginHost?
    private(set) var closedTabs = ClosedTabStack()
    private var blockingEnabled = true
    private var runtimeAllowlist: Set<String> = []
    private var watcher: DirectoryWatcher?
    private var keyMonitor: Any?
    private var sessionSaveTimer: Timer?

    var activeWorkspaceIndex: Int {
        workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
    }

    var activeWorkspace: Workspace {
        get { workspaces[activeWorkspaceIndex] }
        set { workspaces[activeWorkspaceIndex] = newValue }
    }

    func tab(_ id: UUID) -> Tab? {
        for ws in workspaces {
            if let t = ws.tab(id) { return t }
        }
        return nil
    }

    // MARK: Boot

    func boot() {
        do {
            try Profile.ensureScaffold()
        } catch {
            banner = "profile: \(error.localizedDescription)"
        }
        store = try? DataStore(path: Profile.databasePath)
        favicons.onUpdate = { [weak self] in self?.objectWillChange.send() }
        reloadConfig()
        registerCoreCommands()
        restoreOrSeedSession()
        installKeyMonitor()
        watcher = DirectoryWatcher(urls: [Profile.baseURL, Profile.themesURL, Profile.snippetsURL]) { [weak self] in
            self?.reloadConfig()
        }
        let host = PluginHost(model: self)
        pluginHost = host
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            host.loadEnabled()
        }
    }

    func reloadConfig() {
        let (loaded, warnings) = AppConfig.load(from: Profile.configURL)
        let firstLoad = workspaces.isEmpty
        config = loaded
        theme = Theme.load(name: loaded.appearance.theme, themesDir: Profile.themesURL)
        keymap = Keymap(user: Keymap.loadUser(from: Profile.keymapURL))
        if firstLoad {
            sidebarVisible = loaded.layout.sidebarVisible
        }
        blockingEnabled = loaded.privacy.blockTrackers
        webViews.reloadUserStyles()
        reloadContentRules()
        if let warning = warnings.first ?? keymap.warnings.first {
            banner = warning
        } else if !firstLoad {
            banner = nil
        }
    }

    // MARK: Content blocking

    func reloadContentRules() {
        guard blockingEnabled else {
            webViews.apply(ruleList: nil)
            return
        }
        let blocklist = ContentBlocker.loadBlocklist(from: Profile.blocklistURL)
        let allow = blocklist.allowlist + config.privacy.allowlist + Array(runtimeAllowlist)
        guard let json = ContentBlocker.rulesJSON(domains: blocklist.domains, allowlist: allow, rawRules: blocklist.rawRules) else { return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "browser-blocklist", encodedContentRuleList: json) { [weak self] list, error in
            DispatchQueue.main.async {
                if let error {
                    self?.banner = "blocklist: \(error.localizedDescription)"
                    return
                }
                self?.webViews.apply(ruleList: list)
            }
        }
    }

    func toggleShields() {
        blockingEnabled.toggle()
        reloadContentRules()
        banner = blockingEnabled ? "content blocking on" : "content blocking off until the next config reload"
    }

    func toggleSiteShields() {
        guard let host = activeWorkspace.activeTabID.flatMap({ tab($0)?.url?.host }) else { return }
        if runtimeAllowlist.contains(host) {
            runtimeAllowlist.remove(host)
            banner = "blocking restored on \(host)"
        } else {
            runtimeAllowlist.insert(host)
            banner = "trackers allowed on \(host) until quit"
        }
        reloadContentRules()
        webViews.reload()
    }

    // MARK: Downloads

    func downloadStarted(id: UUID) {
        downloads.append(DownloadItem(id: id))
    }

    func downloadNamed(id: UUID, filename: String) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].filename = filename
    }

    func downloadProgress(id: UUID, fraction: Double) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].fraction = fraction
    }

    func downloadFinished(id: UUID, error: String?) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].fraction = 1
        if let error {
            downloads[i].state = .failed(error)
            banner = "download failed: \(error)"
        } else {
            downloads[i].state = .done
        }
    }

    private func restoreOrSeedSession() {
        if config.app.restoreSession, let snapshot = store?.loadSession(), !snapshot.workspaces.isEmpty {
            let (restored, activeIndex) = snapshot.restore()
            workspaces = restored
            activeWorkspaceID = restored[activeIndex].id
        }
        if workspaces.isEmpty {
            var ws = Workspace(name: "Home")
            let tab = Tab()
            ws.tabs = [tab]
            ws.activeTabID = tab.id
            ws.paneTabIDs = [tab.id]
            workspaces = [ws]
            activeWorkspaceID = ws.id
        }
    }

    func scheduleSessionSave() {
        sessionSaveTimer?.invalidate()
        sessionSaveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.saveSessionNow() }
        }
    }

    func saveSessionNow() {
        guard !workspaces.isEmpty else { return }
        store?.saveSession(SessionSnapshot.capture(workspaces: workspaces, activeWorkspaceID: activeWorkspaceID))
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL? = nil, parentID: UUID? = nil, activate: Bool = true) -> UUID {
        let tab = Tab(url: url, title: url?.host ?? "New Tab", parentID: parentID)
        var ws = activeWorkspace
        ws.tabs.append(tab)
        if activate {
            ws.activeTabID = tab.id
            if ws.paneTabIDs.isEmpty {
                ws.paneTabIDs = [tab.id]
            } else {
                ws.paneTabIDs[ws.focusedPane] = tab.id
            }
        }
        activeWorkspace = ws
        if url == nil {
            openOmnibox()
        }
        scheduleSessionSave()
        return tab.id
    }

    func closeTab(_ id: UUID? = nil) {
        var ws = activeWorkspace
        guard let target = id ?? ws.activeTabID,
              let index = ws.tabs.firstIndex(where: { $0.id == target }) else { return }
        let closed = ws.tabs.remove(at: index)
        if closed.url != nil {
            closedTabs.push(ClosedTab(url: closed.url, title: closed.title, pinned: closed.pinned, workspaceID: ws.id))
        }
        for i in ws.tabs.indices where ws.tabs[i].parentID == closed.id {
            ws.tabs[i].parentID = closed.parentID
        }
        let fallback = ws.tabs.indices.contains(index) ? ws.tabs[index].id : ws.tabs.last?.id
        if ws.activeTabID == target { ws.activeTabID = fallback }
        for i in ws.paneTabIDs.indices where ws.paneTabIDs[i] == target {
            if let fallback, !ws.paneTabIDs.contains(fallback) {
                ws.paneTabIDs[i] = fallback
            } else {
                ws.paneTabIDs.remove(at: i)
                ws.focusedPane = max(0, min(ws.focusedPane, ws.paneTabIDs.count - 1))
                break
            }
        }
        if ws.tabs.isEmpty {
            let tab = Tab()
            ws.tabs = [tab]
            ws.activeTabID = tab.id
            ws.paneTabIDs = [tab.id]
        }
        activeWorkspace = ws
        webViews.discard(tabID: target)
        scheduleSessionSave()
    }

    func reopenTab() {
        guard let record = closedTabs.pop() else { return }
        if workspaces.contains(where: { $0.id == record.workspaceID }) {
            activeWorkspaceID = record.workspaceID
        }
        let id = newTab(url: record.url)
        if record.pinned {
            updateTab(id) { $0.pinned = true }
        }
        if let url = record.url {
            navigate(tabID: id, to: url)
        }
    }

    func selectTab(_ id: UUID) {
        var ws = activeWorkspace
        guard ws.tab(id) != nil else { return }
        ws.activeTabID = id
        if ws.paneTabIDs.isEmpty {
            ws.paneTabIDs = [id]
        } else if !ws.paneTabIDs.contains(id) {
            ws.paneTabIDs[ws.focusedPane] = id
        } else if let pane = ws.paneTabIDs.firstIndex(of: id) {
            ws.focusedPane = pane
        }
        activeWorkspace = ws
        scheduleSessionSave()
    }

    func cycleTab(_ delta: Int) {
        let ws = activeWorkspace
        let rows = ws.displayRows()
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.tab.id == ws.activeTabID } ?? 0
        let next = (current + delta + rows.count) % rows.count
        selectTab(rows[next].tab.id)
    }

    func togglePin(_ id: UUID? = nil) {
        var ws = activeWorkspace
        guard let target = id ?? ws.activeTabID,
              let index = ws.tabs.firstIndex(where: { $0.id == target }) else { return }
        ws.tabs[index].pinned.toggle()
        activeWorkspace = ws
        scheduleSessionSave()
    }

    func updateTab(_ id: UUID, mutate: (inout Tab) -> Void) {
        for wi in workspaces.indices {
            if let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == id }) {
                mutate(&workspaces[wi].tabs[ti])
                scheduleSessionSave()
                return
            }
        }
    }

    func navigate(tabID: UUID, to url: URL) {
        updateTab(tabID) { $0.url = url; $0.isLoading = true }
        webViews.load(url: url, in: tabID)
    }

    // MARK: Workspaces

    func newWorkspace() {
        var ws = Workspace(name: "Workspace \(workspaces.count + 1)")
        let tab = Tab()
        ws.tabs = [tab]
        ws.activeTabID = tab.id
        ws.paneTabIDs = [tab.id]
        workspaces.append(ws)
        activeWorkspaceID = ws.id
        scheduleSessionSave()
    }

    func switchWorkspace(_ index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        activeWorkspaceID = workspaces[index].id
        scheduleSessionSave()
    }

    func cycleWorkspace(_ delta: Int) {
        guard !workspaces.isEmpty else { return }
        switchWorkspace((activeWorkspaceIndex + delta + workspaces.count) % workspaces.count)
    }

    // MARK: Panes

    func splitRight() {
        var ws = activeWorkspace
        guard ws.paneTabIDs.count < config.layout.paneMax, let active = ws.activeTabID else { return }
        let candidate = ws.tabs.first { !ws.paneTabIDs.contains($0.id) && $0.id != active }
        let tabID: UUID
        if let candidate {
            tabID = candidate.id
        } else {
            tabID = newTab(activate: false)
        }
        ws = activeWorkspace
        ws.paneTabIDs.append(tabID)
        ws.focusedPane = ws.paneTabIDs.count - 1
        ws.activeTabID = tabID
        activeWorkspace = ws
        scheduleSessionSave()
    }

    func closePane() {
        var ws = activeWorkspace
        guard ws.paneTabIDs.count > 1 else { return }
        ws.paneTabIDs.remove(at: ws.focusedPane)
        ws.focusedPane = max(0, min(ws.focusedPane, ws.paneTabIDs.count - 1))
        ws.activeTabID = ws.paneTabIDs[ws.focusedPane]
        activeWorkspace = ws
        scheduleSessionSave()
    }

    func focusNextPane() {
        var ws = activeWorkspace
        guard ws.paneTabIDs.count > 1 else { return }
        ws.focusedPane = (ws.focusedPane + 1) % ws.paneTabIDs.count
        ws.activeTabID = ws.paneTabIDs[ws.focusedPane]
        activeWorkspace = ws
    }

    // MARK: Find in page

    func openFind() {
        guard activeWorkspace.activeTabID != nil else { return }
        closeOverlays()
        findMatched = nil
        showFind = true
    }

    func closeFind() {
        showFind = false
        findMatched = nil
        webViews.clearSelection()
    }

    func findNext(forward: Bool = true) {
        guard !findText.isEmpty else { return }
        if !showFind {
            showFind = true
        }
        webViews.find(findText, forward: forward) { [weak self] matched in
            self?.findMatched = matched
        }
    }

    // MARK: Omnibox and palette

    func openOmnibox() {
        showPalette = false
        omniboxText = activeWorkspace.activeTabID.flatMap { tab($0)?.url?.absoluteString } ?? ""
        omniboxSelection = 0
        refreshOmniboxSuggestions()
        showOmnibox = true
    }

    func openPalette() {
        showOmnibox = false
        paletteText = ""
        paletteSelection = 0
        showPalette = true
    }

    func closeOverlays() {
        showOmnibox = false
        showPalette = false
    }

    func refreshOmniboxSuggestions() {
        var out: [OmniboxSuggestion] = []
        let query = omniboxText.trimmingCharacters(in: .whitespaces)
        if let action = OmniboxClassifier.classify(query, search: config.search) {
            switch action {
            case .navigate(let url):
                out.append(OmniboxSuggestion(kind: .action, title: url.absoluteString, detail: "Open", url: url))
            case .search(let engine, let q):
                out.append(OmniboxSuggestion(kind: .action, title: q, detail: "Search \(engine.name)", url: engine.searchURL(for: q)))
            }
        }
        if !query.isEmpty {
            let ws = activeWorkspace
            for t in ws.tabs where t.id != ws.activeTabID {
                let target = "\(t.title) \(t.url?.absoluteString ?? "")"
                if FuzzyMatch.score(query: query, target: target) != nil, out.count < 4 {
                    out.append(OmniboxSuggestion(kind: .openTab(t.id), title: t.title, detail: "Switch to tab", url: t.url))
                }
            }
            if let store {
                for entry in store.suggest(query, limit: 8) {
                    guard let url = URL(string: entry.url) else { continue }
                    out.append(OmniboxSuggestion(kind: .history, title: entry.title.isEmpty ? entry.url : entry.title, detail: entry.url, url: url))
                }
            }
        }
        omniboxSuggestions = out
        omniboxSelection = min(omniboxSelection, max(0, out.count - 1))
    }

    func commitOmnibox(newTab openInNewTab: Bool = false) {
        defer { closeOverlays() }
        guard !omniboxSuggestions.isEmpty else { return }
        let choice = omniboxSuggestions[min(omniboxSelection, omniboxSuggestions.count - 1)]
        if case .openTab(let tabID) = choice.kind {
            selectTab(tabID)
            return
        }
        guard let url = choice.url else { return }
        if openInNewTab || activeWorkspace.activeTabID == nil {
            let id = newTab(url: url)
            navigate(tabID: id, to: url)
        } else if let active = activeWorkspace.activeTabID {
            navigate(tabID: active, to: url)
        }
    }

    func commitPalette() {
        let matches = commands.paletteCommands(query: paletteText)
        defer { closeOverlays() }
        guard !matches.isEmpty else { return }
        let index = min(paletteSelection, matches.count - 1)
        matches[index].action()
    }

    // MARK: Key handling

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord.from(event: event) else { return false }
        if showFind, !showOmnibox, !showPalette, chord.key == "escape" {
            closeFind()
            return true
        }
        if showOmnibox || showPalette {
            switch chord.key {
            case "escape":
                closeOverlays()
                return true
            case "down" where !chord.cmd, "up" where !chord.cmd:
                let delta = chord.key == "down" ? 1 : -1
                if showOmnibox {
                    let count = max(omniboxSuggestions.count, 1)
                    omniboxSelection = (omniboxSelection + delta + count) % count
                } else {
                    let count = max(commands.paletteCommands(query: paletteText).count, 1)
                    paletteSelection = (paletteSelection + delta + count) % count
                }
                return true
            case "enter":
                if showOmnibox {
                    commitOmnibox(newTab: chord.cmd)
                } else {
                    commitPalette()
                }
                return true
            default:
                return false
            }
        }
        guard let commandID = keymap.command(for: chord) else { return false }
        return commands.execute(commandID)
    }

    // MARK: Core commands

    private func registerCoreCommands() {
        let defs: [(String, String, String, () -> Void)] = [
            ("tab.new", "New Tab", "Tab", { [weak self] in self?.newTab() }),
            ("tab.close", "Close Tab", "Tab", { [weak self] in self?.closeTab() }),
            ("tab.next", "Next Tab", "Tab", { [weak self] in self?.cycleTab(1) }),
            ("tab.prev", "Previous Tab", "Tab", { [weak self] in self?.cycleTab(-1) }),
            ("tab.pin-toggle", "Pin or Unpin Tab", "Tab", { [weak self] in self?.togglePin() }),
            ("tab.reopen", "Reopen Closed Tab", "Tab", { [weak self] in self?.reopenTab() }),
            ("workspace.new", "New Workspace", "Workspace", { [weak self] in self?.newWorkspace() }),
            ("workspace.next", "Next Workspace", "Workspace", { [weak self] in self?.cycleWorkspace(1) }),
            ("workspace.prev", "Previous Workspace", "Workspace", { [weak self] in self?.cycleWorkspace(-1) }),
            ("pane.split-right", "Split Right", "Pane", { [weak self] in self?.splitRight() }),
            ("pane.close", "Close Pane", "Pane", { [weak self] in self?.closePane() }),
            ("pane.focus-next", "Focus Next Pane", "Pane", { [weak self] in self?.focusNextPane() }),
            ("sidebar.toggle", "Toggle Sidebar", "Layout", { [weak self] in self?.sidebarVisible.toggle() }),
            ("omnibox.open", "Open Location", "Navigate", { [weak self] in self?.openOmnibox() }),
            ("palette.open", "Command Palette", "App", { [weak self] in self?.openPalette() }),
            ("nav.back", "Back", "Navigate", { [weak self] in self?.webViews.goBack() }),
            ("nav.forward", "Forward", "Navigate", { [weak self] in self?.webViews.goForward() }),
            ("nav.reload", "Reload Page", "Navigate", { [weak self] in self?.webViews.reload() }),
            ("zoom.in", "Zoom In", "Page", { [weak self] in self?.webViews.zoom(by: 0.1) }),
            ("zoom.out", "Zoom Out", "Page", { [weak self] in self?.webViews.zoom(by: -0.1) }),
            ("zoom.reset", "Reset Zoom", "Page", { [weak self] in self?.webViews.zoomReset() }),
            ("find.open", "Find in Page", "Page", { [weak self] in self?.openFind() }),
            ("find.next", "Find Next", "Page", { [weak self] in self?.findNext() }),
            ("find.prev", "Find Previous", "Page", { [weak self] in self?.findNext(forward: false) }),
            ("shields.toggle", "Toggle Content Blocking", "Privacy", { [weak self] in self?.toggleShields() }),
            ("shields.site", "Allow or Block Trackers on This Site", "Privacy", { [weak self] in self?.toggleSiteShields() }),
            ("downloads.reveal", "Show Downloads Folder", "App", { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.config.downloads.resolvedURL)
            }),
            ("downloads.clear", "Clear Finished Downloads", "App", { [weak self] in
                self?.downloads.removeAll { $0.state != .running }
            }),
            ("config.reload", "Reload Config and Theme", "App", { [weak self] in self?.reloadConfig() }),
            ("session.save", "Save Session Now", "App", { [weak self] in self?.saveSessionNow() }),
        ]
        for (id, title, category, action) in defs {
            commands.register(Command(id: id, title: title, category: category, action: action))
        }
        for i in 1...9 {
            commands.register(Command(id: "workspace.switch-\(i)", title: "Switch to Workspace \(i)", category: "Workspace", paletteVisible: false) { [weak self] in
                self?.switchWorkspace(i - 1)
            })
        }
    }
}

extension KeyChord {
    static func from(event: NSEvent) -> KeyChord? {
        var chord = KeyChord(key: "")
        let flags = event.modifierFlags
        chord.cmd = flags.contains(.command)
        chord.ctrl = flags.contains(.control)
        chord.alt = flags.contains(.option)
        chord.shift = flags.contains(.shift)
        switch event.keyCode {
        case 36, 76: chord.key = "enter"
        case 48: chord.key = "tab"
        case 49: chord.key = "space"
        case 51: chord.key = "delete"
        case 53: chord.key = "escape"
        case 123: chord.key = "left"
        case 124: chord.key = "right"
        case 125: chord.key = "down"
        case 126: chord.key = "up"
        default:
            guard let chars = event.charactersIgnoringModifiers, let first = chars.first else { return nil }
            let lowered = String(first).lowercased()
            chord.key = KeyChord.unshifted[lowered] ?? lowered
        }
        return chord
    }
}
