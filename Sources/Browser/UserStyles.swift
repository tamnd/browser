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

    static func script(for css: String, hosts: [String] = []) -> WKUserScript {
        WKUserScript(source: injectionJS(css: css, hosts: hosts), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    // An empty host list applies everywhere; otherwise the page host must
    // equal an entry or be a subdomain of one.
    static func injectionJS(css: String, hosts: [String] = []) -> String {
        let encodedCSS = encode(css) ?? "\"\""
        let encodedHosts = encode(hosts) ?? "[]"
        return """
        (function() {
            var hosts = \(encodedHosts);
            if (hosts.length && !hosts.some(function(h) {
                return location.host === h || location.host.slice(-h.length - 1) === '.' + h;
            })) { return; }
            var style = document.createElement('style');
            style.setAttribute('data-browser-snippet', '');
            style.textContent = \(encodedCSS);
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
