import Foundation

struct ThemeSpec: Codable {
    var name: String?
    var variants: [String: [String: String]]?
    var tokens: [String: String]?
}

struct Theme: Equatable {
    var name: String
    var light: [String: String]
    var dark: [String: String]

    static let defaultLight: [String: String] = [
        "bg.base": "#f5f4f0",
        "bg.surface": "#ecebe6",
        "bg.raised": "#ffffff",
        "fg.primary": "#1d1d1f",
        "fg.muted": "#6e6e73",
        "fg.faint": "#a1a1a6",
        "accent": "#4a6fa5",
        "border": "#d9d8d2",
        "tab.active.bg": "#e2e1da",
        "tab.hover.bg": "#eae9e3",
        "palette.bg": "#ffffff",
        "palette.selection": "#e6ecf5",
    ]

    static let defaultDark: [String: String] = [
        "bg.base": "#1e1f22",
        "bg.surface": "#26272b",
        "bg.raised": "#2e2f34",
        "fg.primary": "#e6e6e8",
        "fg.muted": "#9a9aa1",
        "fg.faint": "#5f5f66",
        "accent": "#7aa2f7",
        "border": "#36373d",
        "tab.active.bg": "#34353b",
        "tab.hover.bg": "#2b2c31",
        "palette.bg": "#2a2b30",
        "palette.selection": "#3a3f4d",
    ]

    static let builtin = Theme(name: "graphite", light: [:], dark: [:])

    func token(_ key: String, dark isDark: Bool) -> String {
        if isDark {
            return dark[key] ?? Theme.defaultDark[key] ?? light[key] ?? Theme.defaultLight[key] ?? "#ff00ff"
        }
        return light[key] ?? Theme.defaultLight[key] ?? dark[key] ?? Theme.defaultDark[key] ?? "#ff00ff"
    }

    // Parses #rgb, #rrggbb, and #rrggbbaa into 0...1 components.
    static func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            let r = Double((value >> 16) & 0xff) / 255
            let g = Double((value >> 8) & 0xff) / 255
            let b = Double(value & 0xff) / 255
            return (r, g, b, 1)
        }
        let r = Double((value >> 24) & 0xff) / 255
        let g = Double((value >> 16) & 0xff) / 255
        let b = Double((value >> 8) & 0xff) / 255
        let a = Double(value & 0xff) / 255
        return (r, g, b, a)
    }

    static func load(name: String, themesDir: URL) -> Theme {
        let url = themesDir.appendingPathComponent(name, isDirectory: true).appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: url),
              let spec = try? JSONDecoder().decode(ThemeSpec.self, from: data) else {
            return .builtin
        }
        var light = spec.variants?["light"] ?? [:]
        var dark = spec.variants?["dark"] ?? [:]
        if let flat = spec.tokens {
            light = flat.merging(light) { _, b in b }
            dark = flat.merging(dark) { _, b in b }
        }
        return Theme(name: spec.name ?? name, light: light, dark: dark)
    }
}
