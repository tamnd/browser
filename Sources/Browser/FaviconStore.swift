import AppKit
import Foundation

// Fetches /favicon.ico once per host and caches it in the profile's
// favicons/ folder. Hosts that fail stay marked missing until relaunch.
@MainActor
final class FaviconStore {
    private var memory: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private var inflight: Set<String> = []
    var onUpdate: (() -> Void)?

    nonisolated static func filename(for host: String) -> String {
        let safe = host.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "." || ch == "-") ? ch : "_"
        }
        return String(safe) + ".ico"
    }

    private func fileURL(for host: String) -> URL {
        Profile.faviconsURL.appendingPathComponent(Self.filename(for: host))
    }

    func image(for host: String?) -> NSImage? {
        guard let host, !host.isEmpty else { return nil }
        if let cached = memory[host] { return cached }
        guard !missing.contains(host) else { return nil }
        if let img = NSImage(contentsOf: fileURL(for: host)), img.isValid {
            memory[host] = img
            return img
        }
        return nil
    }

    func fetchIfNeeded(for pageURL: URL?) {
        guard let host = pageURL?.host, !host.isEmpty,
              memory[host] == nil, !missing.contains(host), !inflight.contains(host),
              !FileManager.default.fileExists(atPath: fileURL(for: host).path),
              let iconURL = URL(string: "https://\(host)/favicon.ico") else { return }
        inflight.insert(host)
        let target = fileURL(for: host)
        URLSession.shared.dataTask(with: iconURL) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                self.inflight.remove(host)
                guard ok, let data, let img = NSImage(data: data), img.isValid else {
                    self.missing.insert(host)
                    return
                }
                try? data.write(to: target)
                self.memory[host] = img
                self.onUpdate?()
            }
        }.resume()
    }
}
