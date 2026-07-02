import Foundation

// Turns the profile's blocklist.json into WebKit content rule JSON.
// Compilation through WKContentRuleListStore happens in AppModel.
enum ContentBlocker {
    static let defaultDomains: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "adnxs.com", "adsrvr.org",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "scorecardresearch.com", "quantserve.com", "moatads.com", "doubleverify.com",
        "amazon-adsystem.com", "hotjar.com", "mixpanel.com", "fullstory.com",
        "chartbeat.com", "branch.io", "pubmatic.com", "rubiconproject.com",
        "openx.net", "casalemedia.com", "33across.com",
    ]

    struct Blocklist {
        var domains: [String]
        var allowlist: [String]
        var rawRules: [[String: Any]]
    }

    static func loadBlocklist(from url: URL) -> Blocklist {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Blocklist(domains: defaultDomains, allowlist: [], rawRules: [])
        }
        return Blocklist(
            domains: obj["domains"] as? [String] ?? defaultDomains,
            allowlist: obj["allowlist"] as? [String] ?? [],
            rawRules: obj["rules"] as? [[String: Any]] ?? []
        )
    }

    static func escapeForRegex(_ domain: String) -> String {
        domain.replacingOccurrences(of: ".", with: "\\.")
    }

    // One block rule per domain, third-party loads only, then any raw rules
    // from the file, then one ignore-previous-rules rule per allowlisted site
    // so its pages load whole.
    static func rules(domains: [String], allowlist: [String], rawRules: [[String: Any]] = []) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for domain in domains where !domain.isEmpty {
            out.append([
                "trigger": [
                    "url-filter": "^https?://([^:/]+\\.)?\(escapeForRegex(domain))[:/]",
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ])
        }
        out.append(contentsOf: rawRules)
        for host in allowlist where !host.isEmpty {
            out.append([
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": ["*\(host)"],
                ],
                "action": ["type": "ignore-previous-rules"],
            ])
        }
        return out
    }

    static func rulesJSON(domains: [String], allowlist: [String], rawRules: [[String: Any]] = []) -> String? {
        let list = rules(domains: domains, allowlist: allowlist, rawRules: rawRules)
        guard JSONSerialization.isValidJSONObject(list),
              let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
