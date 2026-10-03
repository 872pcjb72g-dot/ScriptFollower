import Foundation

/// Keeps a teleprompter's place in a script while the reader talks.
///
/// Feed it everything the speech recognizer has heard so far and it answers with the index of the
/// script word the reader is on. It is forgiving by design: people skip words, repeat themselves,
/// say "um", and recognizers mishear. It only ever moves forward, and it only jumps far ahead on a
/// strong match, so a phrase that repeats further down the script cannot steal the reader's place.
///
/// Pure Foundation: no audio, no UI, fully unit-testable.
public struct ScriptAligner {

    /// How many of the most recent heard words take part in a match.
    public static let tailLength = 6
    /// How far ahead of the current place a match may land (a skipped sentence, a fast reader).
    public static let lookAhead = 40
    /// How far behind: recognizers revise their last words, so the tail can end a little back.
    public static let lookBehind = 3

    public let script: [String]

    /// Index of the last script word the reader has said; `-1` before the first match.
    /// Set it to re-anchor, e.g. after the reader scrolls by hand.
    public var currentIndex: Int = -1

    public init(script text: String) {
        self.script = Self.normalizedWords(in: text)
    }

    public init(scriptWords: [String]) {
        self.script = scriptWords
    }

    // MARK: - Normalization

    /// Lowercased, accent- and width-folded, punctuation-free form of a word.
    public static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The words of `text`, normalized, in order, with empty tokens dropped.
    public static func normalizedWords(in text: String) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { word, _, _, _ in
            let n = normalize(word ?? "")
            if !n.isEmpty { words.append(n) }
        }
        return words
    }

    // MARK: - Alignment

    /// Feed the recognizer's whole transcript so far (normalized words).
    /// Returns `true` when the position moved forward; read `currentIndex` for the new place.
    @discardableResult
    public mutating func consume(heard: [String]) -> Bool {
        guard let last = heard.last, !script.isEmpty else { return false }
        let tail = Array(heard.suffix(Self.tailLength))

        let from = max(0, currentIndex - Self.lookBehind)
        let to = min(script.count - 1, max(currentIndex, 0) + Self.lookAhead)
        guard from <= to else { return false }

        var bestEnd = -1, bestScore = 0
        for j in from...to where Self.wordsMatch(last, script[j]) {
            let score = scoreTail(tail, endingAt: j)
            // Prefer the nearest of equally good places: a repeated phrase further down must not win.
            let nearer = bestEnd >= 0 && abs(j - currentIndex) < abs(bestEnd - currentIndex)
            if score > bestScore || (score == bestScore && nearer) {
                bestScore = score
                bestEnd = j
            }
        }
        guard bestEnd > currentIndex else { return false }

        let jump = bestEnd - currentIndex
        let started = currentIndex >= 0
        // The next few words need little evidence; a long jump needs a phrase, not a word.
        let needed = !started ? (jump <= 3 ? 1 : 2) : (jump <= 3 ? 1 : (jump <= 12 ? 2 : 3))
        // Short words ("a", "the", "to") alone never move the reader.
        if bestScore == 1 && last.count <= 2 { return false }
        guard bestScore >= needed else { return false }

        currentIndex = bestEnd
        return true
    }

    /// Longest common subsequence between the heard tail and the script words ending at `end`.
    func scoreTail(_ tail: [String], endingAt end: Int) -> Int {
        let start = max(0, end - (tail.count + 2) + 1)
        let window = Array(script[start...end])
        let n = tail.count, m = window.count
        guard n > 0, m > 0 else { return 0 }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                table[i][j] = Self.wordsMatch(tail[i - 1], window[j - 1])
                    ? table[i - 1][j - 1] + 1
                    : max(table[i - 1][j], table[i][j - 1])
            }
        }
        return table[n][m]
    }

    // MARK: - Word similarity

    /// Same word as far as following a reader goes: exact, a plural/tense away, or one typo off.
    static func wordsMatch(_ heard: String, _ script: String) -> Bool {
        if heard == script { return true }
        let shorter = min(heard.count, script.count)
        guard shorter >= 3 else { return false }
        if shorter >= 4, heard.hasPrefix(script) || script.hasPrefix(heard),
           max(heard.count, script.count) - shorter <= 3 { return true }
        let cap = shorter >= 8 ? 2 : 1
        return editDistance(heard, script, cap: cap) <= cap
    }

    /// Levenshtein distance with an early exit once it exceeds `cap`.
    static func editDistance(_ a: String, _ b: String, cap: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > cap { return cap + 1 }
        var prev = Array(0...b.count), cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            cur[0] = i
            var rowMin = cur[0]
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > cap { return cap + 1 }
            swap(&prev, &cur)
        }
        return a.isEmpty ? b.count : prev[b.count]
    }
}
