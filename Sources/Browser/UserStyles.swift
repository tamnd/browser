import Foundation
import WebKit

enum UserStyles {
    static func loadSnippets(from dir: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names
            .filter { $0.hasSuffix(".css") }
            .sorted()
            .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func script(for css: String) -> WKUserScript {
        WKUserScript(source: injectionJS(css: css), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    static func injectionJS(css: String) -> String {
        let encoded = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function() {
            var style = document.createElement('style');
            style.setAttribute('data-browser-snippet', '');
            style.textContent = \(encoded);
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
