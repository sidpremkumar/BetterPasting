import Foundation

enum FuzzyMatcher {

    /// Filter clipboard items by fuzzy matching against searchable text and source app name
    static func filter(_ items: [ClipboardItem], query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }

        let lowercaseQuery = query.lowercased()

        var scoredItems: [(item: ClipboardItem, score: Int)] = []

        for item in items {
            var bestScore: Int? = nil

            // Match against content
            let contentText = item.searchableText.lowercased()
            if !contentText.isEmpty {
                if let (score, _) = fuzzyMatch(contentText, pattern: lowercaseQuery) {
                    bestScore = max(bestScore ?? 0, score + 100)
                }
            }

            // Match against source app name
            if let appName = item.sourceAppName?.lowercased() {
                if let (score, _) = fuzzyMatch(appName, pattern: lowercaseQuery) {
                    bestScore = max(bestScore ?? 0, score + 50)
                }
            }

            // Match against source bundle ID
            if let bundleID = item.sourceBundleID?.lowercased() {
                if let (score, _) = fuzzyMatch(bundleID, pattern: lowercaseQuery) {
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

    private static func fuzzyMatch(_ text: String, pattern: String) -> (score: Int, ranges: [Range<String.Index>])? {
        guard !pattern.isEmpty else { return (0, []) }

        var textIndex = text.startIndex
        var patternIndex = pattern.startIndex
        var matchedRanges: [Range<String.Index>] = []
        var score = 0
        var consecutiveBonus = 0
        var lastMatchIndex: String.Index?

        while textIndex < text.endIndex && patternIndex < pattern.endIndex {
            let textChar = text[textIndex]
            let patternChar = pattern[patternIndex]

            if textChar == patternChar {
                let rangeStart = textIndex
                textIndex = text.index(after: textIndex)
                patternIndex = pattern.index(after: patternIndex)
                matchedRanges.append(rangeStart..<textIndex)

                // Base score for match
                score += 10

                // Consecutive match bonus
                if let lastMatch = lastMatchIndex,
                   text.index(after: lastMatch) == rangeStart {
                    consecutiveBonus += 5
                    score += consecutiveBonus
                } else {
                    consecutiveBonus = 0
                }

                // Word boundary bonus
                if rangeStart == text.startIndex {
                    score += 25  // Match at start of string
                } else {
                    let prevIndex = text.index(before: rangeStart)
                    let prevChar = text[prevIndex]
                    if prevChar == " " || prevChar == "-" || prevChar == "_" || prevChar == "." {
                        score += 15  // Match at word boundary
                    } else if prevChar.isLowercase && textChar.isUppercase {
                        score += 15  // CamelCase boundary
                    }
                }

                lastMatchIndex = rangeStart
            } else {
                textIndex = text.index(after: textIndex)
                consecutiveBonus = 0
            }
        }

        // All pattern characters must be found
        guard patternIndex == pattern.endIndex else {
            return nil
        }

        // Bonus for shorter strings (more relevant matches)
        let lengthBonus = max(0, 50 - text.count)
        score += lengthBonus

        return (score, matchedRanges)
    }
}
