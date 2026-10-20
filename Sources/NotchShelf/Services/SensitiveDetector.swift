import Foundation

/// Cheap local checks for text that looks like a secret, so the shelf can blur it.
enum SensitiveDetector {
    private static let patterns: [NSRegularExpression] = [
        #"sk-[A-Za-z0-9_\-]{20,}"#,                                    // OpenAI / Anthropic-style keys
        #"AKIA[0-9A-Z]{16}"#,                                          // AWS access key id
        #"gh[pousr]_[A-Za-z0-9]{30,}"#,                                // GitHub tokens
        #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,                             // Slack tokens
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,                        // PEM private keys
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, // JWTs
        #"(?i)(password|passwd|secret|api[_\-]?key|token)\s*[:=]\s*\S{6,}"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let cardCandidate = try? NSRegularExpression(pattern: #"\b(?:\d[ \-]?){13,19}\b"#)

    static func looksSensitive(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if patterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) { return true }
        return containsCardNumber(text, range: range)
    }

    private static func containsCardNumber(_ text: String, range: NSRange) -> Bool {
        guard let cardCandidate else { return false }
        for match in cardCandidate.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].compactMap { $0.wholeNumberValue }
            if (13...19).contains(digits.count) && passesLuhn(digits) { return true }
        }
        return false
    }

    private static func passesLuhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
