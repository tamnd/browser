import Foundation

enum ErrorPage {
    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(message: String, url: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Cannot load page</title>
        <style>
        body { font: 15px/1.5 -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; color: #555; background: #fafafa; }
        @media (prefers-color-scheme: dark) { body { color: #aaa; background: #1e1e1e; } }
        main { max-width: 32em; padding: 2em; text-align: center; }
        h1 { font-size: 1.2em; }
        code { font-size: 13px; word-break: break-all; }
        </style></head>
        <body><main>
        <h1>This page did not load</h1>
        <p>\(escapeHTML(message))</p>
        <p><code>\(escapeHTML(url))</code></p>
        <p>Reload with cmd+r once the problem is fixed.</p>
        </main></body></html>
        """
    }
}
