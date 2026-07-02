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

struct Keymap: Equatable {
    private(set) var bindings: [KeyChord: String]
    private(set) var warnings: [String]

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

    init(user: [String: String?] = [:]) {
        var resolved: [KeyChord: String] = [:]
        var warns: [String] = []
        for (raw, command) in Keymap.defaults {
            guard let chord = KeyChord.parse(raw) else { continue }
            resolved[chord] = command
        }
        for (raw, command) in user {
            guard let chord = KeyChord.parse(raw) else {
                warns.append("keymap: cannot parse chord \"\(raw)\"")
                continue
            }
            if let command, !command.isEmpty {
                resolved[chord] = command
            } else {
                resolved.removeValue(forKey: chord)
            }
        }
        bindings = resolved
        warnings = warns
    }

    func command(for chord: KeyChord) -> String? {
        bindings[chord]
    }

    func chord(for commandID: String) -> KeyChord? {
        bindings.first { $0.value == commandID }?.key
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
