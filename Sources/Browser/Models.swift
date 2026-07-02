import Foundation

struct Tab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var title: String
    var pinned: Bool
    var parentID: UUID?
    var isLoading: Bool

    init(id: UUID = UUID(), url: URL? = nil, title: String = "New Tab", pinned: Bool = false, parentID: UUID? = nil, isLoading: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.pinned = pinned
        self.parentID = parentID
        self.isLoading = isLoading
    }
}

struct Workspace: Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: String
    // Keys the persistent WKWebsiteDataStore, so each workspace has its own
    // cookies and storage that survive relaunch through the session snapshot.
    var containerID: UUID
    var tabs: [Tab]
    var activeTabID: UUID?
    var paneTabIDs: [UUID]
    var focusedPane: Int

    init(id: UUID = UUID(), name: String, color: String = "#7aa2f7", containerID: UUID = UUID(), tabs: [Tab] = [], activeTabID: UUID? = nil, paneTabIDs: [UUID] = [], focusedPane: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.containerID = containerID
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.paneTabIDs = paneTabIDs
        self.focusedPane = focusedPane
    }

    func tab(_ id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    // Sidebar order: pinned tabs first, then roots in insertion order with children under their parent.
    func displayRows() -> [(tab: Tab, depth: Int)] {
        var rows: [(Tab, Int)] = []
        let pinned = tabs.filter { $0.pinned }
        for t in pinned { rows.append((t, 0)) }
        let unpinned = tabs.filter { !$0.pinned }
        let childrenByParent = Dictionary(grouping: unpinned.filter { $0.parentID != nil }, by: { $0.parentID! })
        let ids = Set(unpinned.map { $0.id })
        func walk(_ tab: Tab, depth: Int) {
            rows.append((tab, depth))
            for child in childrenByParent[tab.id] ?? [] {
                walk(child, depth: min(depth + 1, 4))
            }
        }
        for t in unpinned where t.parentID == nil || !ids.contains(t.parentID!) {
            walk(t, depth: 0)
        }
        return rows
    }
}

struct SessionSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var workspaces: [WorkspaceSnapshot]
    var activeWorkspaceIndex: Int
}

struct WorkspaceSnapshot: Codable, Equatable {
    var name: String
    var color: String
    var containerID: String?
    var tabs: [TabSnapshot]
    var activeTabIndex: Int?
}

struct TabSnapshot: Codable, Equatable {
    var url: String?
    var title: String
    var pinned: Bool
    var parentIndex: Int?
}

extension SessionSnapshot {
    static func capture(workspaces: [Workspace], activeWorkspaceID: UUID) -> SessionSnapshot {
        let wss = workspaces.map { ws -> WorkspaceSnapshot in
            let indexByID = Dictionary(uniqueKeysWithValues: ws.tabs.enumerated().map { ($1.id, $0) })
            let tabs = ws.tabs.map { t in
                TabSnapshot(url: t.url?.absoluteString, title: t.title, pinned: t.pinned, parentIndex: t.parentID.flatMap { indexByID[$0] })
            }
            let active = ws.activeTabID.flatMap { indexByID[$0] }
            return WorkspaceSnapshot(name: ws.name, color: ws.color, containerID: ws.containerID.uuidString, tabs: tabs, activeTabIndex: active)
        }
        let activeIndex = workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
        return SessionSnapshot(schemaVersion: 2, workspaces: wss, activeWorkspaceIndex: activeIndex)
    }

    func restore() -> (workspaces: [Workspace], activeIndex: Int) {
        var result: [Workspace] = []
        for ws in workspaces {
            var tabs: [Tab] = []
            for snap in ws.tabs {
                tabs.append(Tab(url: snap.url.flatMap { URL(string: $0) }, title: snap.title, pinned: snap.pinned))
            }
            for (i, snap) in ws.tabs.enumerated() {
                if let p = snap.parentIndex, p >= 0, p < tabs.count, p != i {
                    tabs[i].parentID = tabs[p].id
                }
            }
            let container = ws.containerID.flatMap { UUID(uuidString: $0) } ?? UUID()
            var workspace = Workspace(name: ws.name, color: ws.color, containerID: container, tabs: tabs)
            if let a = ws.activeTabIndex, a >= 0, a < tabs.count {
                workspace.activeTabID = tabs[a].id
                workspace.paneTabIDs = [tabs[a].id]
            } else if let first = tabs.first {
                workspace.activeTabID = first.id
                workspace.paneTabIDs = [first.id]
            }
            result.append(workspace)
        }
        let active = (activeWorkspaceIndex >= 0 && activeWorkspaceIndex < result.count) ? activeWorkspaceIndex : 0
        return (result, active)
    }
}

struct ClosedTab: Equatable {
    var url: URL?
    var title: String
    var pinned: Bool
    var workspaceID: UUID
}

// Bounded LIFO of recently closed tabs backing tab.reopen.
struct ClosedTabStack: Equatable {
    static let limit = 50
    private(set) var records: [ClosedTab] = []

    mutating func push(_ record: ClosedTab) {
        records.append(record)
        if records.count > Self.limit {
            records.removeFirst(records.count - Self.limit)
        }
    }

    mutating func pop() -> ClosedTab? {
        records.popLast()
    }
}

struct DownloadItem: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case done
        case failed(String)
    }

    let id: UUID
    var filename: String = "download"
    var fraction: Double = 0
    var state: State = .running
}
