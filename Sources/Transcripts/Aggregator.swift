import Foundation
import Prices

public struct TokenGroup: Sendable, Equatable {
    public var name: String
    public var key: String        // the model id, the project name or the session id
    public var tokens: Int
    public var share: Int         // percent of the list's total
    public init(name: String, key: String, tokens: Int, share: Int) { self.name = name; self.key = key; self.tokens = tokens; self.share = share }
}

public struct TokenSummary: Sendable, Equatable {
    public var byModel7d: [TokenGroup]
    public var byProject7d: [TokenGroup]
    public var bySessionToday: [TokenGroup]
    public var agentShare7d: Int          // percent
    public var listPrice7d: Double
    public var unpricedModels: Int
    public var tokensToday: Int
    public var tokens7d: Int
    public var tokens30d: Int
    public var total7d: Int
    public var totalToday: Int
    public init(byModel7d: [TokenGroup], byProject7d: [TokenGroup], bySessionToday: [TokenGroup], agentShare7d: Int,
                listPrice7d: Double, unpricedModels: Int, tokensToday: Int, tokens7d: Int, tokens30d: Int, total7d: Int, totalToday: Int) {
        self.byModel7d = byModel7d; self.byProject7d = byProject7d; self.bySessionToday = bySessionToday
        self.agentShare7d = agentShare7d; self.listPrice7d = listPrice7d; self.unpricedModels = unpricedModels
        self.tokensToday = tokensToday; self.tokens7d = tokens7d; self.tokens30d = tokens30d; self.total7d = total7d; self.totalToday = totalToday
    }
}

public enum Aggregator {
    public static let maxRows = 5

    /// Groups sorted by the figure, largest first; more than five becomes four and "other".
    public static func groups(_ records: [UsageRecord], key: (UsageRecord) -> String, name: (String) -> String) -> [TokenGroup] {
        var sums: [String: Int] = [:]
        for r in records { sums[key(r), default: 0] += r.usage.total }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        var sorted = sums.map { ($0.key, $0.value) }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        var out: [TokenGroup] = []
        if sorted.count > maxRows {
            let rest = sorted[(maxRows - 1)...].reduce(0) { $0 + $1.1 }
            sorted = Array(sorted.prefix(maxRows - 1))
            out = sorted.map { TokenGroup(name: name($0.0), key: $0.0, tokens: $0.1, share: Int((Double($0.1) / Double(total) * 100).rounded())) }
            out.append(TokenGroup(name: "other", key: "other", tokens: rest, share: Int((Double(rest) / Double(total) * 100).rounded())))
        } else {
            out = sorted.map { TokenGroup(name: name($0.0), key: $0.0, tokens: $0.1, share: Int((Double($0.1) / Double(total) * 100).rounded())) }
        }
        return out
    }

    public static func summarize(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current) -> TokenSummary {
        let midnight = calendar.startOfDay(for: now)
        let d7 = now.addingTimeInterval(-7 * 24 * 3600)
        let d30 = now.addingTimeInterval(-30 * 24 * 3600)
        let today = records.filter { $0.timestamp >= midnight && $0.timestamp <= now }
        let week = records.filter { $0.timestamp >= d7 && $0.timestamp <= now }
        let month = records.filter { $0.timestamp >= d30 && $0.timestamp <= now }
        let total7 = week.reduce(0) { $0 + $1.usage.total }
        let agent7 = week.filter(\.isAgent).reduce(0) { $0 + $1.usage.total }
        var price = 0.0
        var unpriced: Set<String> = []
        for r in week {
            if let c = PriceTable.cost(model: r.model, usage: r.usage) { price += c } else { unpriced.insert(r.model) }
        }
        return TokenSummary(
            byModel7d: groups(week, key: \.model, name: { PriceTable.displayName(forModel: $0) }),
            byProject7d: groups(week, key: \.project, name: { $0 }),
            bySessionToday: groups(today, key: \.session, name: { String($0.prefix(8)) }),
            agentShare7d: total7 > 0 ? Int((Double(agent7) / Double(total7) * 100).rounded()) : 0,
            listPrice7d: price, unpricedModels: unpriced.count,
            tokensToday: today.reduce(0) { $0 + $1.usage.total }, tokens7d: total7, tokens30d: month.reduce(0) { $0 + $1.usage.total },
            total7d: total7, totalToday: today.reduce(0) { $0 + $1.usage.total })
    }
}
