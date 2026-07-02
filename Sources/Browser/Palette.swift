import Foundation

// One palette, three modes, picked by the first character:
// bare text navigates or searches, ">" runs commands, "#" jumps to a tab.
enum PaletteMode: Equatable {
    case navigate
    case command
    case tabs

    static func parse(_ text: String) -> (mode: PaletteMode, query: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") {
            return (.command, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        if trimmed.hasPrefix("#") {
            return (.tabs, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        return (.navigate, trimmed)
    }

    var placeholder: String {
        switch self {
        case .navigate: return "Search or enter address"
        case .command: return "Type a command"
        case .tabs: return "Jump to a tab"
        }
    }
}

enum PaletteRow: Identifiable {
    case command(Command)
    case suggestion(OmniboxSuggestion)
    case tab(tabID: UUID, workspaceIndex: Int, title: String, detail: String)

    var id: String {
        switch self {
        case .command(let cmd): return "cmd:\(cmd.id)"
        case .suggestion(let s): return "sug:\(s.id.uuidString)"
        case .tab(let tabID, _, _, _): return "tab:\(tabID.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .command(let cmd): return cmd.title
        case .suggestion(let s): return s.title
        case .tab(_, _, let title, _): return title
        }
    }
}
