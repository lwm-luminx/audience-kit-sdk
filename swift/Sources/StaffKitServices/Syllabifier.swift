import Foundation

/// Splits a lyric line into syllables for the caption highlight, without changing a character: the pieces join back
/// into the line exactly, each word's spaces and punctuation riding on its last syllable. English spelling rules (vowel
/// groups, a consonant between vowels starts the next syllable, two split between, digraphs kept whole, a silent
/// final e, "-le"), which is good enough to sweep a highlight; the timing tool (tools/velvet-align) counts syllables
/// with CMUdict and hands back its own boundaries, which win when there are any.
public enum Syllabifier {
    /// The line in syllables, joining back to `line` exactly.
    public static func syllables(_ line: String) -> [String] {
        var pieces: [String] = []
        var lead = ""
        var word = ""
        var tail = ""
        func flush() {
            var parts = split(word: word)
            guard !parts.isEmpty else { return }
            parts[0] = lead + parts[0]
            parts[parts.count - 1] += tail
            pieces += parts
            lead = ""; word = ""; tail = ""
        }
        for character in line {
            if character.isLetter || character.isNumber || (!word.isEmpty && (character == "'" || character == "\u{2019}")) {
                if !tail.isEmpty { flush() }
                word.append(character)
            } else if word.isEmpty {
                // Before a line's first word ("(Oh"): it rides on that word's first syllable.
                lead.append(character)
            } else {
                tail.append(character)
            }
        }
        flush()
        // A line with no letters at all ("♪", "..."): one piece, itself.
        if pieces.isEmpty, !lead.isEmpty { pieces = [lead] }
        return pieces
    }

    static let digraphs: Set<String> = ["ch", "sh", "th", "ph", "wh", "ck", "ng", "gh", "qu"]

    /// One word in syllables (letters only, or with apostrophes).
    static func split(word: String) -> [String] {
        let letters = Array(word)
        guard letters.count > 3 else { return word.isEmpty ? [] : [word] }
        let lower = letters.map { Character($0.lowercased()) }
        func vowel(_ index: Int) -> Bool {
            guard lower.indices.contains(index) else { return false }
            let c = lower[index]
            if "aeiouáéíóúàèìòùäëïöüâêîôû".contains(c) { return true }
            // "y" is a vowel after a consonant ("rhythm", "my"), a consonant at a word's start ("you").
            return c == "y" && index > 0 && !vowel(index - 1)
        }
        // The vowel groups, as (start, end) indexes, end exclusive.
        var nuclei: [(Int, Int)] = []
        var index = 0
        while index < lower.count {
            if vowel(index) {
                let start = index
                while index < lower.count && vowel(index) {
                    index += 1
                    // A vowel "y" ends its syllable before another vowel ("fy-ing", "cry-ing").
                    if lower[index - 1] == "y" && vowel(index) { break }
                }
                nuclei.append((start, index))
            } else {
                index += 1
            }
        }
        // A final "e" after a consonant is silent ("love", "time"), unless it's "-le" after a consonant ("little").
        if nuclei.count > 1, let last = nuclei.last, last.0 == lower.count - 1, lower[last.0] == "e",
           !(lower.count >= 3 && lower[lower.count - 2] == "l" && !vowel(lower.count - 3)) {
            nuclei.removeLast()
        }
        // "-ed" after anything but t or d is one syllable with the one before ("loved", "jumped").
        if nuclei.count > 1, lower.count >= 3, lower[lower.count - 1] == "d", let last = nuclei.last,
           last == (lower.count - 2, lower.count - 1), lower[lower.count - 2] == "e",
           !["t", "d"].contains(lower[lower.count - 3]) {
            nuclei.removeLast()
        }
        guard nuclei.count > 1 else { return [word] }
        var cuts: [Int] = []
        for (left, right) in zip(nuclei, nuclei.dropFirst()) {
            let consonants = right.0 - left.1
            switch consonants {
            case 0:
                cuts.append(right.0)
            case 1:
                cuts.append(left.1)
            default:
                // Keep a digraph ("ch", "th") or "-le" together on the next syllable; else split after the first.
                let lastTwo = String(lower[(right.0 - 2)..<right.0])
                if digraphs.contains(lastTwo) || (lastTwo.last == "l" && right.1 == lower.count && lower.last == "e") {
                    cuts.append(right.0 - 2)
                } else {
                    let firstTwo = String(lower[left.1..<(left.1 + 2)])
                    cuts.append(digraphs.contains(firstTwo) ? left.1 + 2 : left.1 + 1)
                }
            }
        }
        var parts: [String] = []
        var start = 0
        for cut in cuts where cut > start && cut < letters.count {
            parts.append(String(letters[start..<cut]))
            start = cut
        }
        parts.append(String(letters[start...]))
        return parts
    }
}
