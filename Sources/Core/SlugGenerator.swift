import Foundation

public enum SlugGenerator {

    /// Converts arbitrary text into a kebab-case filename slug, max `maxLength` characters.
    /// "Welcome to Settings — General" → "welcome-to-settings-general"
    public static func slug(from text: String, maxLength: Int = 50) -> String {
        var result = text.lowercased()

        // Replace anything that isn't alphanumeric or whitespace with a space
        result = result.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )
        // Collapse runs of whitespace to a single hyphen
        result = result.replacingOccurrences(
            of: "\\s+",
            with: "-",
            options: .regularExpression
        )
        // Collapse multiple consecutive hyphens
        result = result.replacingOccurrences(
            of: "-{2,}",
            with: "-",
            options: .regularExpression
        )
        // Strip leading/trailing hyphens
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !result.isEmpty else { return "untitled" }
        guard result.count > maxLength else { return result }

        // Truncate at the last word boundary within maxLength
        let truncated = String(result.prefix(maxLength))
        if let lastHyphen = truncated.lastIndex(of: "-") {
            let clean = String(truncated[..<lastHyphen])
            return clean.isEmpty ? truncated : clean
        }
        return truncated
    }

    /// Scores how suitable an OCR text line is as a filename.
    /// Higher score = better candidate. Penalises all-caps labels, pure numbers, and very short strings.
    public static func meaningScore(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return 0 }

        var score = trimmed.count
        let letters = trimmed.filter { $0.isLetter }
        score += letters.count * 2

        // Penalise all-caps (usually UI labels like "OK", "CANCEL", "MENU")
        if trimmed == trimmed.uppercased() { score -= 15 }

        // Penalise very short lines
        if trimmed.count < 5 { score -= 20 }

        // Penalise lines that are mostly non-alphabetic (timestamps, hex codes, etc.)
        let alphaRatio = trimmed.isEmpty ? 0.0 : Double(letters.count) / Double(trimmed.count)
        if alphaRatio < 0.4 { score -= 10 }

        return score
    }
}
