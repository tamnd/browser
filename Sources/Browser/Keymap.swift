import Foundation

struct KeyChord: Hashable, CustomStringConvertible {
    var cmd = false
    var ctrl = false
    var alt = false
    var shift = false
    var key: String

    var description: String {
        var parts: [String] = []
        if cmd { parts.append("cmd") }
        if ctrl { parts.append("ctrl") }
        if alt { parts.append("alt") }
        if shift { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    static let namedKeys: Set<String> = [
        "enter", "escape", "space", "tab", "delete", "up", "down", "left", "right", "home", "end", "pageup", "pagedown",
    ]

    static let aliases: [String: String] = [
        "esc": "escape", "return": "enter", "backspace": "delete",
        "opt": "alt", "option": "alt", "meta": "cmd", "super": "cmd", "command": "cmd", "control": "ctrl",
    ]

    // Map shifted US-layout symbols back to their base key so
    // "cmd+shift+[" matches the "{" the event reports.
    static let unshifted: [String: String] = [
        "{": "[", "}": "]", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`", "|": "\\",
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=",
    ]

    static func parse(_ raw: String) -> KeyChord? {
        let parts = raw.lowercased().split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }
        var chord = KeyChord(key: "")
        for (i, part0) in parts.enumerated() {
            let part = aliases[part0] ?? part0
            let isLast = i == parts.count - 1
            switch part {
            case "cmd" where !isLast: chord.cmd = true
            case "ctrl" where !isLast: chord.ctrl = true
            case "alt" where !isLast: chord.alt = true
            case "shift" where !isLast: chord.shift = true
            default:
                guard isLast else { return nil }
                if namedKeys.contains(part) || part.count == 1 || part.range(of: "^f[0-9]{1,2}$", options: .regularExpression) != nil {
                    chord.key = unshifted[part] ?? part
                } else {
                    return nil
                }
            }
        }
        guard !chord.key.isEmpty else { return nil }
        return chord
    }
}

// A binding is one or more chords typed in order, like "g t".
struct KeySequence: Hashable, CustomStringConvertible {
    var chords: [KeyChord]

    init(_ chords: [KeyChord]) {
        self.chords = chords
    }

    static func parse(_ raw: String) -> KeySequence? {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }
        var chords: [KeyChord] = []
        for part in parts {
            guard let chord = KeyChord.parse(part) else { return nil }
            chords.append(chord)
        }
        return KeySequence(chords)
    }

    func isPrefix(of other: KeySequence) -> Bool {
        chords.count < other.chords.count && Array(other.chords.prefix(chords.count)) == chords
    }

    var description: String {
        chords.map(\.description).joined(separator: " ")
    }
}

struct Keymap: Equatable {
    private(set) var bindings: [KeySequence: String]
    private(set) var warnings: [String]

    enum Match: Equatable {
        case none
        case prefix
        case command(String)
    }

    static let defaults: [String: String] = [
        "cmd+t": "tab.new",
        "cmd+w": "tab.close",
        "cmd+shift+]": "tab.next",
        "cmd+shift+[": "tab.prev",
        "ctrl+tab": "tab.next",
        "ctrl+shift+tab": "tab.prev",
        "cmd+p": "tab.pin-toggle",
        "cmd+shift+t": "tab.reopen",
        "cmd+f": "find.open",
        "cmd+g": "find.next",
        "cmd+shift+g": "find.prev",
        "cmd+l": "omnibox.open",
        "cmd+k": "palette.open",
        "cmd+shift+k": "tab.search",
        "cmd+b": "sidebar.toggle",
        "cmd+[": "nav.back",
        "cmd+]": "nav.forward",
        "cmd+r": "nav.reload",
        "cmd+shift+d": "pane.split-right",
        "cmd+shift+w": "pane.close",
        "cmd+shift+f": "pane.focus-next",
        "cmd+shift+n": "workspace.new",
        "cmd+shift+.": "workspace.next",
        "cmd+shift+,": "workspace.prev",
        "cmd+=": "zoom.in",
        "cmd+-": "zoom.out",
        "cmd+0": "zoom.reset",
        "cmd+1": "workspace.switch-1",
        "cmd+2": "workspace.switch-2",
        "cmd+3": "workspace.switch-3",
        "cmd+4": "workspace.switch-4",
        "cmd+5": "workspace.switch-5",
        "cmd+6": "workspace.switch-6",
        "cmd+7": "workspace.switch-7",
        "cmd+8": "workspace.switch-8",
        "cmd+9": "workspace.switch-9",
    ]

    // Layering: defaults, then plugin suggestions, then the user file. User always wins.
    init(user: [String: String?] = [:], suggested: [String: String] = [:]) {
        var resolved: [KeySequence: String] = [:]
        var warns: [String] = []
        for (raw, command) in Keymap.defaults {
            guard let sequence = KeySequence.parse(raw) else { continue }
            resolved[sequence] = command
        }
        for (raw, command) in suggested {
            guard let sequence = KeySequence.parse(raw) else {
                warns.append("plugin keymap: cannot parse \"\(raw)\"")
                continue
            }
            resolved[sequence] = command
        }
        for (raw, command) in user {
            guard let sequence = KeySequence.parse(raw) else {
                warns.append("keymap: cannot parse chord \"\(raw)\"")
                continue
            }
            if let command, !command.isEmpty {
                resolved[sequence] = command
            } else {
                resolved.removeValue(forKey: sequence)
            }
        }
        // A binding that is also the start of a longer one fires immediately
        // and makes the longer one unreachable, so say so at load time.
        for (sequence, command) in resolved {
            if let shadowed = resolved.keys.first(where: { sequence.isPrefix(of: $0) }) {
                warns.append("keymap: \"\(sequence)\" (\(command)) hides the longer binding \"\(shadowed)\"")
            }
        }
        bindings = resolved
        warnings = warns.sorted()
    }

    func match(_ chords: [KeyChord]) -> Match {
        let candidate = KeySequence(chords)
        if let command = bindings[candidate] {
            return .command(command)
        }
        if bindings.keys.contains(where: { candidate.isPrefix(of: $0) }) {
            return .prefix
        }
        return .none
    }

    func command(for chord: KeyChord) -> String? {
        bindings[KeySequence([chord])]
    }

    func sequence(for commandID: String) -> KeySequence? {
        bindings.filter { $0.value == commandID }.keys.min { $0.description < $1.description }
    }

    static func loadUser(from url: URL) -> [String: String?] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: String?] = [:]
        for (k, v) in obj {
            if k.hasPrefix("_") { continue }
            if v is NSNull {
                out[k] = String?.none
            } else if let s = v as? String {
                out[k] = s
            }
        }
        return out
    }
}
