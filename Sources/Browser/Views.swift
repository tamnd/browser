import AppKit
import SwiftUI
import WebKit

extension Theme {
    func color(_ key: String, _ scheme: ColorScheme) -> Color {
        let hex = token(key, dark: scheme == .dark)
        guard let c = Theme.hexComponents(hex) else { return .pink }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView()
                        .frame(width: model.config.layout.sidebarWidth)
                    Rectangle()
                        .fill(model.theme.color("border", scheme))
                        .frame(width: 1)
                }
                PaneAreaView()
            }
            if model.showFind {
                FindBarView()
            }
            if let banner = model.banner {
                BannerView(text: banner)
            }
            if model.showPalette {
                PaletteOverlay()
            }
            if let pending = model.pendingKeys {
                PendingKeysView(keys: pending)
            }
        }
        .background(model.theme.color("bg.base", scheme))
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch model.config.appearance.variant {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct BannerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
            Button("Dismiss") { model.banner = nil }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(10)
        .background(model.theme.color("bg.raised", scheme))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.color("border", scheme)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 480)
        .padding(.top, 8)
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceStrip
                .padding(.horizontal, 10)
                .padding(.top, 38)
                .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.activeWorkspace.displayRows(), id: \.tab.id) { row in
                        TabRowView(tab: row.tab, depth: row.depth)
                    }
                }
                .padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
            if !model.downloads.isEmpty {
                DownloadsSectionView()
            }
            Button {
                model.commands.execute("tab.new")
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Tab")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(model.theme.color("fg.muted", scheme))
                .padding(8)
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .background(model.theme.color("bg.surface", scheme))
    }

    private var workspaceStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element.id) { index, ws in
                let isActive = ws.id == model.activeWorkspaceID
                Button {
                    model.switchWorkspace(index)
                } label: {
                    Text(ws.name.prefix(1).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(
                                isActive
                                    ? model.theme.color("accent", scheme)
                                    : model.theme.color("bg.raised", scheme)
                            )
                        )
                        .foregroundStyle(isActive ? Color.white : model.theme.color("fg.muted", scheme))
                }
                .buttonStyle(.plain)
                .help(ws.name)
            }
            Button {
                model.commands.execute("workspace.new")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(model.theme.color("fg.faint", scheme))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

struct TabRowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    let tab: Tab
    let depth: Int
    @State private var hovering = false

    var body: some View {
        let isActive = tab.id == model.activeWorkspace.activeTabID
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else if tab.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(model.theme.color("fg.faint", scheme))
                    .frame(width: 12)
            } else if let icon = model.favicons.image(for: tab.url?.host) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(model.theme.color("fg.faint", scheme))
                    .frame(width: 12)
            }
            Text(tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(model.theme.color(isActive ? "fg.primary" : "fg.muted", scheme))
            Spacer(minLength: 0)
            if hovering {
                Button {
                    model.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(model.theme.color("fg.faint", scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 8 + CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(
                isActive
                    ? model.theme.color("tab.active.bg", scheme)
                    : hovering ? model.theme.color("tab.hover.bg", scheme) : Color.clear
            )
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectTab(tab.id) }
        .onHover { hovering = $0 }
    }
}

struct DownloadsSectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Downloads")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.theme.color("fg.muted", scheme))
                Spacer()
                Button("Clear") {
                    model.commands.execute("downloads.clear")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(model.theme.color("fg.faint", scheme))
            }
            ForEach(model.downloads.suffix(4)) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: item.state))
                            .font(.system(size: 9))
                            .foregroundStyle(model.theme.color("fg.faint", scheme))
                        Text(item.filename)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(model.theme.color("fg.primary", scheme))
                    }
                    if item.state == .running {
                        ProgressView(value: item.fraction)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.color("bg.raised", scheme)))
        .padding(6)
    }

    private func icon(for state: DownloadItem.State) -> String {
        switch state {
        case .running: return "arrow.down.circle"
        case .done: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }
}

struct FindBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(model.theme.color("fg.faint", scheme))
            TextField("Find in page", text: $model.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 180)
                .focused($focused)
                .onChange(of: model.findText) {
                    model.findNext()
                }
                .onSubmit {
                    model.findNext()
                }
            if model.findMatched == false {
                Text("No matches")
                    .font(.system(size: 11))
                    .foregroundStyle(model.theme.color("fg.faint", scheme))
            }
            Button { model.findNext(forward: false) } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            Button { model.findNext() } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            Button { model.closeFind() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(model.theme.color("fg.muted", scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(model.theme.color("bg.raised", scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.color("border", scheme)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 10)
        .padding(.trailing, 16)
        .onAppear { focused = true }
    }
}

struct PaneAreaView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let ws = model.activeWorkspace
        HStack(spacing: 1) {
            ForEach(Array(ws.paneTabIDs.enumerated()), id: \.offset) { index, tabID in
                paneView(tabID: tabID, focused: index == ws.focusedPane && ws.paneTabIDs.count > 1)
            }
        }
        .background(model.theme.color("border", scheme))
    }

    @ViewBuilder
    private func paneView(tabID: UUID, focused: Bool) -> some View {
        ZStack {
            if let tab = model.tab(tabID), tab.url != nil {
                WebViewContainer(tabID: tabID)
            } else {
                NewTabView()
            }
        }
        .overlay(
            Rectangle()
                .stroke(focused ? model.theme.color("accent", scheme) : Color.clear, lineWidth: 2)
        )
    }
}

struct NewTabView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 12) {
            Text("browser")
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .foregroundStyle(model.theme.color("fg.faint", scheme))
            Text("cmd+l to go somewhere, cmd+k for commands")
                .font(.system(size: 13))
                .foregroundStyle(model.theme.color("fg.muted", scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.theme.color("bg.base", scheme))
        .contentShape(Rectangle())
        .onTapGesture { model.openOmnibox() }
    }
}

struct WebViewContainer: NSViewRepresentable {
    @EnvironmentObject var model: AppModel
    let tabID: UUID

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let web = model.webViews.webView(for: tabID)
        guard web.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        web.frame = view.bounds
        web.autoresizingMask = [.width, .height]
        view.addSubview(web)
    }
}

struct PaletteOverlay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    @FocusState private var focused: Bool

    var body: some View {
        let mode = PaletteMode.parse(model.paletteText).mode
        VStack(spacing: 0) {
            TextField(mode.placeholder, text: $model.paletteText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .focused($focused)
                .onChange(of: model.paletteText) {
                    model.paletteSelection = 0
                    model.refreshPalette()
                }
                .onSubmit {
                    model.commitPalette()
                }
            if !model.paletteRows.isEmpty {
                Rectangle().fill(model.theme.color("border", scheme)).frame(height: 1)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.paletteRows.enumerated()), id: \.element.id) { index, row in
                            SuggestionRow(
                                title: row.title,
                                detail: detail(for: row),
                                selected: index == model.paletteSelection
                            )
                            .onTapGesture {
                                model.paletteSelection = index
                                model.commitPalette()
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
        }
        .overlayCard(theme: model.theme, scheme: scheme)
        .onAppear { focused = true }
    }

    private func detail(for row: PaletteRow) -> String {
        switch row {
        case .command(let command):
            return model.keymap.sequence(for: command.id)?.description ?? command.category
        case .suggestion(let suggestion):
            return suggestion.detail
        case .tab(_, _, _, let detail):
            return detail
        }
    }
}

struct PendingKeysView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(model.theme.color("fg.muted", scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(model.theme.color("bg.raised", scheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.theme.color("border", scheme)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(16)
    }
}

struct SuggestionRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    let title: String
    let detail: String
    let selected: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(model.theme.color("fg.primary", scheme))
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(model.theme.color("fg.faint", scheme))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? model.theme.color("palette.selection", scheme) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct OverlayCard: ViewModifier {
    let theme: Theme
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        VStack {
            content
                .background(theme.color("palette.bg", scheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.color("border", scheme)))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                .frame(width: 640)
                .padding(.top, 120)
            Spacer()
        }
    }
}

private extension View {
    func overlayCard(theme: Theme, scheme: ColorScheme) -> some View {
        modifier(OverlayCard(theme: theme, scheme: scheme))
    }
}
