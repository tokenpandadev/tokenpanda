import Foundation

// The bundled price table, spec section 6. Source: platform.claude.com/docs/en/about-claude/pricing, read 2026-10-13.
// USD per million tokens. Five columns because the cache read multiplier differs per model. Never fetched.

public struct Usage: Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var cacheWrite5m: Int?
    public var cacheWrite1h: Int?
    public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, cacheWrite5m: Int? = nil, cacheWrite1h: Int? = nil) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
        self.cacheWrite5m = cacheWrite5m; self.cacheWrite1h = cacheWrite1h
    }
    public var total: Int { input + output + cacheRead + cacheWrite }
    /// The prompt size for a tiered price: everything the model read.
    public var promptSize: Int { input + cacheRead + cacheWrite }
}

public struct PriceRow: Sendable, Equatable {
    public var name: String
    public var idPrefix: String
    public var input: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    public var cacheRead: Double
    public var output: Double
    public var idVerified: Bool            // the id string was seen in a transcript on the build Mac
    public var longPromptFrom: Int?        // Haiku 5.5: a second tier for prompts over this many tokens
    public var longPrompt: [Double]?       // input, 5m, 1h, read, output for the long tier

    public func cost(_ u: Usage) -> Double {
        var p = (input, cacheWrite5m, cacheWrite1h, cacheRead, output)
        if let from = longPromptFrom, let l = longPrompt, u.promptSize > from { p = (l[0], l[1], l[2], l[3], l[4]) }
        let w5: Int, w1: Int
        if let a = u.cacheWrite5m, let b = u.cacheWrite1h, a + b > 0 { w5 = a; w1 = b } else { w5 = u.cacheWrite; w1 = 0 }
        let m = 1_000_000.0
        return Double(u.input) * p.0 / m + Double(w5) * p.1 / m + Double(w1) * p.2 / m
            + Double(u.cacheRead) * p.3 / m + Double(u.output) * p.4 / m
    }
}

public enum PriceTable {
    public static let readDate = "2026-10-13"
    public static let source = "platform.claude.com/docs/en/about-claude/pricing"

    public static let rows: [PriceRow] = [
        PriceRow(name: "Fable 5.1", idPrefix: "claude-fable-5-1", input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50, idVerified: true),
        PriceRow(name: "Opus 5.5", idPrefix: "claude-opus-5-5", input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20, output: 20, idVerified: true),
        PriceRow(name: "Opus 5", idPrefix: "claude-opus-5", input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25, idVerified: true),
        // to be verified: the id strings of the next four were not seen in a transcript; they follow the pattern of the seen ids
        PriceRow(name: "Opus 4.8", idPrefix: "claude-opus-4-8", input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.50, output: 25, idVerified: false),
        PriceRow(name: "Sonnet 5.5", idPrefix: "claude-sonnet-5-5", input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.10, output: 10, idVerified: false),
        PriceRow(name: "Sonnet 5", idPrefix: "claude-sonnet-5", input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.20, output: 10, idVerified: false),
        PriceRow(name: "Haiku 5.5", idPrefix: "claude-haiku-5-5", input: 0.10, cacheWrite5m: 0.125, cacheWrite1h: 0.20, cacheRead: 0.01, output: 0.50, idVerified: false,
                 longPromptFrom: 100_000, longPrompt: [0.50, 0.625, 1, 0.05, 2.50]),
        PriceRow(name: "Haiku 4.5", idPrefix: "claude-haiku-4-5", input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10, output: 5, idVerified: true),
    ]

    /// Longest prefix wins, so claude-opus-5-5 is never taken for claude-opus-5.
    public static func row(forModel id: String) -> PriceRow? {
        rows.filter { id == $0.idPrefix || id.hasPrefix($0.idPrefix + "-") }
            .max { $0.idPrefix.count < $1.idPrefix.count }
    }

    /// nil when the model has no row: counted in tokens, skipped in cost.
    public static func cost(model id: String, usage: Usage) -> Double? {
        row(forModel: id)?.cost(usage)
    }

    /// "claude-fable-5-1" is "Fable 5.1", "claude-haiku-4-5-20251001" is "Haiku 4.5". An unknown id is shown as is.
    public static func displayName(forModel id: String) -> String {
        if let r = row(forModel: id) { return r.name }
        guard id.hasPrefix("claude-") else { return id }
        let parts = id.dropFirst("claude-".count).split(separator: "-").map(String.init)
        guard let family = parts.first, !family.isEmpty else { return id }
        var version: [String] = []
        for p in parts.dropFirst() {
            if p.count <= 2, Int(p) != nil { version.append(p) } else { break }
        }
        guard !version.isEmpty else { return id }
        return family.prefix(1).uppercased() + family.dropFirst() + " " + version.joined(separator: ".")
    }

    public static func family(forModel id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        return String(id.dropFirst("claude-".count).split(separator: "-").first ?? "")
    }
}
