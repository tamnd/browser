import Foundation

enum OmniboxAction: Equatable {
    case navigate(URL)
    case search(SearchEngine, String)
}

enum OmniboxClassifier {
    // Order matters: scheme, localhost/IP, engine keyword, dot heuristic, search.
    static func classify(_ raw: String, search: SearchSection) -> OmniboxAction? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if input.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil,
           let url = URL(string: input) {
            return .navigate(url)
        }
        if input.hasPrefix("browser://"), let url = URL(string: input) {
            return .navigate(url)
        }

        let hasSpace = input.contains(" ")

        if !hasSpace {
            if input.range(of: "^localhost(:[0-9]+)?(/.*)?$", options: .regularExpression) != nil,
               let url = URL(string: "http://\(input)") {
                return .navigate(url)
            }
            if input.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]+)?(/.*)?$", options: .regularExpression) != nil,
               let url = URL(string: "http://\(input)") {
                return .navigate(url)
            }
        }

        // Engine keyword: "g rust wkwebview" searches Google.
        if hasSpace {
            let parts = input.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let engine = search.engine(keyword: String(parts[0])) {
                return .search(engine, String(parts[1]))
            }
        }
        var bare = input
        if bare.hasPrefix("!") { bare.removeFirst() }

        if !hasSpace, input.contains("."), input.range(of: "^[^\\s]+\\.[a-zA-Z]{2,}(:[0-9]+)?(/[^\\s]*)?$", options: .regularExpression) != nil,
           input.range(of: "^[0-9.]+$", options: .regularExpression) == nil,
           let url = URL(string: "https://\(input)") {
            return .navigate(url)
        }

        return .search(search.resolvedDefault, input)
    }

    static func url(for action: OmniboxAction) -> URL? {
        switch action {
        case .navigate(let url): return url
        case .search(let engine, let query): return engine.searchURL(for: query)
        }
    }
}

struct OmniboxSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case action
        case openTab(UUID)
        case history
    }
    let id: UUID
    var kind: Kind
    var title: String
    var detail: String
    var url: URL?

    init(kind: Kind, title: String, detail: String, url: URL? = nil) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.detail = detail
        self.url = url
    }

    static func == (lhs: OmniboxSuggestion, rhs: OmniboxSuggestion) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.detail == rhs.detail && lhs.url == rhs.url
    }
}
