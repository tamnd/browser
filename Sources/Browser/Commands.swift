import Foundation

struct Command: Identifiable {
    let id: String
    let title: String
    let category: String
    let paletteVisible: Bool
    let source: String
    let action: () -> Void

    init(id: String, title: String, category: String, paletteVisible: Bool = true, source: String = "core", action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.category = category
        self.paletteVisible = paletteVisible
        self.source = source
        self.action = action
    }
}

final class CommandRegistry {
    private(set) var commands: [String: Command] = [:]

    func register(_ command: Command) {
        commands[command.id] = command
    }

    func unregister(source: String) {
        commands = commands.filter { $0.value.source != source }
    }

    @discardableResult
    func execute(_ id: String) -> Bool {
        guard let command = commands[id] else { return false }
        command.action()
        return true
    }

    func paletteCommands(query: String) -> [Command] {
        let visible = commands.values.filter { $0.paletteVisible }
        if query.isEmpty {
            return visible.sorted { $0.title < $1.title }
        }
        return visible
            .compactMap { cmd -> (Command, Int)? in
                let target = "\(cmd.category): \(cmd.title)"
                guard let score = FuzzyMatch.score(query: query, target: target) ?? FuzzyMatch.score(query: query, target: cmd.id) else { return nil }
                return (cmd, score)
            }
            .sorted { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1 }
            .map { $0.0 }
    }
}
