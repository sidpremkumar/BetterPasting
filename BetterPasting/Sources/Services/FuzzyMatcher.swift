import Foundation

enum FuzzyMatcher {

    /// Filter clipboard items by matching against searchable text and source app name.
    /// Prioritizes exact substring matches over fuzzy character-scattered matches.
    static func filter(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }

        let lowercaseQuery = query.lowercased()

        var scoredItems: [(item: ClipboardItem, score: Int)] = []

        for item in items {
            var bestScore: Int? = nil

            // Match against content
            let contentText = item.searchableText.lowercased()
            if !contentText.isEmpty {
                if let score = matchScore(contentText, query: lowercaseQuery) {
                    bestScore = max(bestScore ?? 0, score + 100)
                }
            }

            // Match against source app name
            if let appName = item.sourceAppName?.lowercased() {
                if let score = matchScore(appName, query: lowercaseQuery) {
                    bestScore = max(bestScore ?? 0, score + 50)
                }
            }

            // Match against source bundle ID
            if let bundleID = item.sourceBundleID?.lowercased() {
                if let score = matchScore(bundleID, query: lowercaseQuery) {
                    bestScore = max(bestScore ?? 0, score)
                }
            }

            if let score = bestScore {
                scoredItems.append((item, score))
            }
        }

        // Sort by score descending, then by creation date descending
        return scoredItems
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.item.createdAt > rhs.item.createdAt
            }
            .map { $0.item }
    }

    /// Score a match. Returns nil if no match.
    /// Priority: exact match > prefix > word-boundary substring > substring > tight fuzzy
    private static func matchScore(_ text: String, query: String) -> Int? {
        // 1. Exact match
        if text == query {
            return 10000
        }

        // 2. Prefix match (text starts with query)
        if text.hasPrefix(query) {
            let lengthBonus = max(0, 100 - text.count)
            return 5000 + lengthBonus
        }

        // 3. Word-boundary substring (query appears right after a space, dash, underscore, dot, or slash)
        if let range = text.range(of: query) {
            let matchStart = range.lowerBound
            if matchStart > text.startIndex {
                let prevChar = text[text.index(before: matchStart)]
                if prevChar == " " || prevChar == "-" || prevChar == "_" || prevChar == "." || prevChar == "/" {
                    let position = text.distance(from: text.startIndex, to: matchStart)
                    let positionPenalty = min(position, 200)
                    return 3000 - positionPenalty
                }
            }
        }

        // 4. Substring match anywhere
        if let range = text.range(of: query) {
            let position = text.distance(from: text.startIndex, to: range.lowerBound)
            let positionPenalty = min(position, 200)
            let lengthBonus = max(0, 50 - text.count)
            return 2000 - positionPenalty + lengthBonus
        }

        // 5. Consecutive word initials (e.g. "hw" matches "hello world")
        if query.count >= 2 {
            if matchesWordInitials(text, query: query) {
                return 1500
            }
        }

        // 6. Tight fuzzy match — all query chars must appear in order,
        //    but penalize heavily for gaps between matched characters.
        //    Only accept if the match is reasonably tight.
        if let score = tightFuzzyMatch(text, query: query) {
            return score
        }

        return nil
    }

    /// Check if query characters match the first letter of consecutive words
    private static func matchesWordInitials(_ text: String, query: String) -> Bool {
        var words: [Character] = []
        var atWordStart = true
        for char in text {
            if atWordStart && char.isLetter {
                words.append(char)
                atWordStart = false
            } else if char == " " || char == "-" || char == "_" || char == "." {
                atWordStart = true
            } else {
                atWordStart = false
            }
        }

        guard words.count >= query.count else { return false }

        var qi = query.startIndex
        var wi = 0
        while qi < query.endIndex && wi < words.count {
            if query[qi] == words[wi] {
                qi = query.index(after: qi)
            }
            wi += 1
        }
        return qi == query.endIndex
    }

    /// Tight fuzzy match: all query characters must appear in order.
    /// Returns a score only if the total gap (non-matched characters between matches)
    /// is small relative to the query length.
    private static func tightFuzzyMatch(_ text: String, query: String) -> Int? {
        guard !query.isEmpty else { return nil }

        var textIndex = text.startIndex
        var patternIndex = query.startIndex
        var totalGap = 0
        var consecutiveRun = 0
        var maxConsecutive = 0
        var lastMatchIndex: String.Index?

        while textIndex < text.endIndex && patternIndex < query.endIndex {
            if text[textIndex] == query[patternIndex] {
                if let last = lastMatchIndex {
                    let gap = text.distance(from: text.index(after: last), to: textIndex)
                    totalGap += gap
                    if gap == 0 {
                        consecutiveRun += 1
                        maxConsecutive = max(maxConsecutive, consecutiveRun)
                    } else {
                        consecutiveRun = 1
                    }
                } else {
                    consecutiveRun = 1
                }
                lastMatchIndex = textIndex
                patternIndex = query.index(after: patternIndex)
            }
            textIndex = text.index(after: textIndex)
        }

        // All pattern characters must be found
        guard patternIndex == query.endIndex else { return nil }

        // Reject if gaps are too large relative to query length
        // Allow at most 2 gap characters per query character
        let queryLen = query.count
        let maxAllowedGap = queryLen * 2
        guard totalGap <= maxAllowedGap else { return nil }

        // Score: base 1000, penalize gaps, bonus for consecutive runs
        let gapPenalty = totalGap * 50
        let consecutiveBonus = maxConsecutive * 30
        let lengthBonus = max(0, 50 - text.count)
        let score = 1000 - gapPenalty + consecutiveBonus + lengthBonus

        // Only return if score is positive (meaningful match)
        return score > 0 ? score : nil
    }
}
