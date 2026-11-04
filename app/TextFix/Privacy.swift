import Foundation
import NaturalLanguage

struct PrivacyOptions {
    let words: [String]
    let findNames: Bool
}

struct Redaction {
    private static let patterns: [(label: String, regex: NSRegularExpression)] = [
        ("EMAIL", #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        ("IBAN", #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b"#),
        ("IP", #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
        ("PHONE", #"(?<![\w+])(?:\+|00|0)\d[\d /().-]{5,}\d"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1, options: $0.0 == "EMAIL" ? [.caseInsensitive] : [])) }

    private static let greetings: Set<String> = [
        "hi", "hello", "hey", "dear", "thanks", "br", "regards", "cheers",
        "hallo", "liebe", "lieber", "viele", "grüße", "gruß", "danke", "servus", "moin",
        "szia", "sziasztok", "kedves", "üdv", "köszi",
    ]

    private let output: NSMutableString
    private var values: [(placeholder: String, value: String)] = []

    var text: String { output as String }
    var isEmpty: Bool { values.isEmpty }

    init(_ text: String, options: PrivacyOptions) {
        output = NSMutableString(string: text)
        for word in options.words.sorted(by: { $0.count > $1.count }) {
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: word)
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                replace(regex, label: "NAME")
            }
        }
        for pattern in Self.patterns {
            replace(pattern.regex, label: pattern.label)
        }
        if options.findNames { replaceNames() }
    }

    func restore(_ text: String) -> String {
        values.reduce(text) { result, item in
            result.replacingOccurrences(of: item.placeholder, with: item.value)
        }
    }

    private mutating func replace(_ regex: NSRegularExpression, label: String) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: output.length))
        replace(matches.map { ($0.range, label) })
    }

    private mutating func replaceNames() {
        let current = text
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = current
        var found: [(NSRange, String)] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: current.startIndex..<current.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let label = tag == .personalName ? "PERSON" : tag == .organizationName ? "COMPANY" : nil
            let word = current[range]
            if let label, !word.contains("_"), !Self.greetings.contains(word.lowercased()) {
                found.append((NSRange(range, in: current), label))
            }
            return true
        }
        replace(found)
    }

    private mutating func replace(_ ranges: [(NSRange, String)]) {
        let placeholders = ranges.map { placeholder(for: output.substring(with: $0.0), label: $0.1) }
        for (range, placeholder) in zip(ranges.map(\.0), placeholders).reversed() {
            output.replaceCharacters(in: range, with: placeholder)
        }
    }

    private mutating func placeholder(for value: String, label: String) -> String {
        if let existing = values.first(where: { $0.placeholder.hasPrefix("[\(label)_") && $0.value.lowercased() == value.lowercased() }) {
            return existing.placeholder
        }
        let number = values.filter { $0.placeholder.hasPrefix("[\(label)_") }.count + 1
        let placeholder = "[\(label)_\(number)]"
        values.append((placeholder, value))
        return placeholder
    }
}
