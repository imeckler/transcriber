import Foundation

enum TranscriptEditing {
    // Keep contractions, hyphenated words, and numbers intact during alignment.
    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*"#)
    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh"]
    private static let sentenceEnds = CharacterSet(charactersIn: ".!?。！？")
    private static let closers = CharacterSet(charactersIn: "’”\"')]}»")
    static func endsSentence(_ text: String) -> Bool {
        text.trimmingCharacters(in: closers.union(.whitespacesAndNewlines)).unicodeScalars.last.map(sentenceEnds.contains) ?? false
    }

    static func edit(_ passage: Passage, suggestion: String, beginsSentence: Bool) -> String {
        let source = passage.text as NSString
        let proposed = suggestion as NSString
        func tokens(_ text: NSString) -> [NSRange] {
            words.matches(in: text as String, range: NSRange(location: 0, length: text.length)).map(\.range)
        }
        let originals = tokens(source), revisions = tokens(proposed)
        var edits: [(NSRange, String)] = []
        var j = 0
        for range in originals {
            let word = source.substring(with: range)
            let candidate = j < revisions.count ? proposed.substring(with: revisions[j]) : ""
            if word.lowercased() == candidate.lowercased() {
                // A suggestion may add capitals to lowercase words. Existing capitals are authoritative.
                if word == word.lowercased(), word != candidate { edits.append((range, candidate)) }
                j += 1
            } else {
                guard passage.english, fillers.contains(word.lowercased()), word == word.lowercased() || word == word.capitalized else {
                    return capitalizeSentences(passage.text, beginsSentence)
                }
                var end = NSMaxRange(range)
                let before = range.location > 0 ? source.substring(with: NSRange(location: range.location-1,length: 1)) : ""
                let after = end < source.length ? source.substring(with: NSRange(location: end,length: 1)) : ""
                // Quoted words and short acronyms can themselves be the subject of speech.
                if ["“","‘","\"","'"].contains(before) || ["”","’","\"","'"].contains(after) {
                    return capitalizeSentences(passage.text, beginsSentence)
                }
                if after == "," { end += 1 }
                while end < source.length && source.character(at: end) == 32 { end += 1 }
                edits.append((NSRange(location: range.location, length: end-range.location), ""))
            }
        }
        guard j == revisions.count else { return capitalizeSentences(passage.text, beginsSentence) }
        let output = NSMutableString(string: passage.text)
        for (range, replacement) in edits.reversed() { output.replaceCharacters(in: range, with: replacement) }
        let text = (output as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return capitalizeSentences(text.rangeOfCharacter(from: .alphanumerics) == nil ? passage.text : text, beginsSentence)
    }

    private static func capitalizeSentences(_ text: String, _ atStart: Bool) -> String {
        let ns = text as NSString
        let result = NSMutableString(string: text)
        let matches = words.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for i in matches.indices.reversed() {
            let range = matches[i].range
            let previous = i == 0 ? 0 : NSMaxRange(matches[i-1].range)
            let gap = ns.substring(with: NSRange(location: previous, length: range.location-previous))
            let boundary = i == 0 ? atStart : (gap.rangeOfCharacter(from: sentenceEnds) != nil && gap.rangeOfCharacter(from: .whitespacesAndNewlines) != nil)
            let word = ns.substring(with: range)
            if boundary, word == word.lowercased(), let first = word.first, first.isLowercase {
                result.replaceCharacters(in: range, with: first.uppercased() + word.dropFirst())
            }
        }
        return result as String
    }

    static func paragraphs(_ passages: [Passage], timestamps: Bool) -> String {
        var paragraphs = [Passage]()
        var previous: Passage?
        for passage in passages {
            let text = passage.text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            guard !text.isEmpty else { continue }
            let gap = previous.map { passage.startMilliseconds - $0.endMilliseconds } ?? 0
            let sentenceEnded = previous.map { endsSentence($0.text) } ?? false
            if let last = paragraphs.last, last.label == passage.label, gap < 3500,
               !(sentenceEnded && (gap >= 1400 || last.text.count >= 460)) {
                let space = separator(last.text.last, text.first)
                paragraphs[paragraphs.count - 1].text += space + text
            } else {
                var first = passage
                first.text = text
                paragraphs.append(first)
            }
            previous = passage
        }
        return paragraphs.map { $0.formatted(timestamps: timestamps) }.joined(separator: "\n\n")
    }

    private static func separator(_ last: Character?, _ first: Character?) -> String {
        guard let first = first, let last = last else { return "" }
        if ".,!?;:，。！？、)]}".contains(first) || "([{".contains(last) { return "" }
        func unspaced(_ c: Character) -> Bool {
            guard let scalar = c.unicodeScalars.first else { return false }
            return (0x3040...0x30ff).contains(scalar.value) || (0x3400...0x9fff).contains(scalar.value)
        }
        return unspaced(first) && (unspaced(last) || "。！？、，".contains(last)) ? "" : " "
    }
}
