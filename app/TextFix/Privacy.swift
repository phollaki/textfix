import Foundation
import NaturalLanguage

struct PrivacyOptions {
    let words: [String]
    let findNames: Bool
}

struct Redaction {
    private static let patterns: [(label: String, regex: NSRegularExpression)] = [
        ("SECRET", #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#),
        ("SECRET", #"\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@\S*"#),
        ("SECRET", #"(?i)(?:password|passwd|pwd|passwort|kennwort|jelszó|jelszava|secret|token|api[ _-]?key|api[ _-]?kulcs|access[ _-]?key)["']?\s*[:=]\s*["']?((?!\[)[^\s"',;]*[^\s"',;.])"#),
        ("SECRET", #"(?i)\b(?:password|passwort|kennwort)\s+(?:is|ist|lautet)\s+["']?((?!\[)[^\s"',;]*[^\s"',;.])"#),
        ("SECRET", #"(?i)\bbearer\s+((?!\[)[A-Za-z0-9._~+/=-]{8,})"#),
        ("SECRET", #"\b(?:sk-[A-Za-z0-9_-]{16,}|[srp]k_(?:live|test)_[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[abeoprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|(?:gsk|hf|npm)_[A-Za-z0-9]{20,})"#),
        ("SECRET", #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+"#),
        ("SECRET", #"\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{32,}\b"#),
        ("EMAIL", #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
        ("IBAN", #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b"#),
        ("CARD", #"\b(?:(?:4\d{3}|5[1-5]\d{2}|6011)[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}|3[47]\d{2}[ -]?\d{6}[ -]?\d{5})\b"#),
        ("ID", #"\b\d{3}-\d{2}-\d{4}\b"#),
        ("ID", #"(?i:\b(?:SSN|TAJ(?:[ -]?szám)?|adóazonosító(?: jel)?|adószám|személyi(?: igazolvány)?(?: szám)?|steuer-?id|steuernummer|ausweisnummer|passport(?: number| no\.?)?|útlevélszám))\s*[:=#]?\s*([A-Z]{0,3}\d[\dA-Z /-]{4,}[\dA-Z])"#),
        ("IP", #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
        ("IP", #"(?<![\w:])(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){7}|(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*)?::[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*|[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4})*::)(?![\w:])"#),
        ("PHONE", #"(?<![\w+./-])(?!\d{1,2}[./-]\d{1,2}[./-]\d{2,4}(?![\d-]))(?!\d{1,2}\.\d{1,2}\.)(?:\+|00|0)\d[\d /().-]{5,}\d"#),
        ("ADDRESS", #"(?:\b\d{4}\s+\p{Lu}\p{L}+,?\s+)?(?:\p{Lu}\p{L}+\s+){1,4}(?:utca|út|útja|tér|tere|körút|krt\.?|köz|sétány|u\.)\s+\d+[/\w-]*"#),
        ("ADDRESS", #"\b\p{Lu}\p{L}*(?:straße|strasse|str\.|gasse|weg|platz|allee)\s+\d+[a-z]?\b(?:,?\s+\d{5}\s+\p{Lu}\p{L}+)?"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1, options: $0.0 == "EMAIL" ? [.caseInsensitive] : [])) }

    private static let notNames: Set<String> = [
        "hi", "hello", "hey", "dear", "thanks", "br", "regards", "cheers",
        "hallo", "liebe", "lieber", "viele", "grüße", "gruß", "danke", "servus", "moin", "mit", "sehr", "herr", "frau",
        "szia", "sziasztok", "kedves", "üdv", "köszi", "köszönöm", "helló", "tisztelt", "tisztelettel", "üdvözlettel", "az", "ez", "egy",
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
        replaceDetected()
        if options.findNames { replaceNames() }
    }

    func restore(_ text: String) -> String {
        values.reduce(text) { result, item in
            result.replacingOccurrences(of: item.placeholder, with: item.value)
        }
    }

    private mutating func replace(_ regex: NSRegularExpression, label: String) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: output.length))
        replace(matches.map { ($0.range(at: $0.numberOfRanges - 1), label) })
    }

    private mutating func replaceDetected() {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return }
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: output.length))
        replace(matches.map { ($0.range, $0.resultType == .phoneNumber ? "PHONE" : "ADDRESS") })
    }

    private mutating func replaceNames() {
        let current = text
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = current
        var found: [String: String] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: current.startIndex..<current.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            let label = tag == .personalName ? "PERSON" : tag == .organizationName ? "COMPANY" : nil
            let word = String(current[range])
            if let label, !word.contains("_"), !Self.notNames.contains(word.lowercased()) {
                found[word] = label
            }
            return true
        }
        for name in Self.capitalizedNames(in: current) where found[name] == nil {
            found[name] = "NAME"
        }
        for (name, label) in found.sorted(by: { $0.key.count > $1.key.count }) {
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}])"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                replace(regex, label: label)
            }
        }
    }

    private static func capitalizedNames(in text: String) -> [String] {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text),
              !NLTagger.availableTagSchemes(for: .word, language: language).contains(.nameType),
              let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.-])\p{Lu}\p{Ll}+(?:[ -]\p{Lu}\p{Ll}+)*(?![\p{L}\p{N}_])"#)
        else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            var words = source.substring(with: match.range).split(separator: " ").map(String.init)
            var index = match.range.location
            while index > 0, [32, 9].contains(source.character(at: index - 1)) { index -= 1 }
            let previous = index > 0 ? source.substring(with: NSRange(location: index - 1, length: 1)) : ""
            var startsSentence = previous.isEmpty || ".!?:\n-•".contains(previous)
            let onOwnLine = previous == "\n" && lineRest(of: match.range, in: source).allSatisfy { " ,.!\n".contains($0) }
            while let first = words.first, notNames.contains(first.lowercased()) {
                words.removeFirst()
                startsSentence = false
            }
            guard !words.isEmpty, words.count > 1 || !startsSentence || onOwnLine else { return nil }
            return words.joined(separator: " ")
        }
    }

    private static func lineRest(of range: NSRange, in source: NSString) -> String {
        let line = source.lineRange(for: range)
        return source.substring(with: NSRange(location: range.upperBound, length: line.upperBound - range.upperBound))
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
        var number = values.filter { $0.placeholder.hasPrefix("[\(label)_") }.count + 1
        while output.contains("[\(label)_\(number)]") { number += 1 }
        let placeholder = "[\(label)_\(number)]"
        values.append((placeholder, value))
        return placeholder
    }
}
