import Foundation

// Subsequence fuzzy matcher for the command palette and omnibox.
// Returns nil when the query is not a subsequence of the target.
enum FuzzyMatch {
    static let consecutiveBonus = 12
    static let boundaryBonus = 10
    static let startBonus = 8
    static let gapPenalty = 1

    static func score(query: String, target: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        let raw = Array(target)
        if q.count > t.count { return nil }

        var score = 0
        var qi = 0
        var lastMatch = -1
        for ti in 0..<t.count {
            guard qi < q.count else { break }
            if t[ti] == q[qi] {
                var s = 1
                if lastMatch == ti - 1 { s += consecutiveBonus }
                if ti == 0 {
                    s += startBonus + boundaryBonus
                } else {
                    let prev = raw[ti - 1]
                    if prev == " " || prev == "." || prev == "-" || prev == "_" || prev == "/" {
                        s += boundaryBonus
                    } else if prev.isLowercase && raw[ti].isUppercase {
                        s += boundaryBonus
                    }
                }
                if lastMatch >= 0 {
                    score -= min(ti - lastMatch - 1, 10) * gapPenalty
                }
                score += s
                lastMatch = ti
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        // Prefer shorter targets when scores tie.
        score -= t.count / 8
        return score
    }
}
