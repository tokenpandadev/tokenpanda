// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Prices

/// One message per row of the table against a hand computed figure.
struct PricesTests {
    let u = Usage(input: 1_000_000, output: 100_000, cacheRead: 2_000_000, cacheWrite: 500_000)

    @Test func fable() {
        // 1M in at 10, 0.1M out at 50, 2M read at 0.25, 0.5M write at 12.50 (5m, no split)
        #expect(abs((PriceTable.cost(model: "claude-fable-5-1", usage: u)!) - (10 + 5 + 0.5 + 6.25)) <= 1e-9)
    }
    @Test func opus55() { #expect(abs((PriceTable.cost(model: "claude-opus-5-5", usage: u)!) - (4 + 2 + 0.4 + 2.5)) <= 1e-9) }
    @Test func opus5() { #expect(abs((PriceTable.cost(model: "claude-opus-5", usage: u)!) - (5 + 2.5 + 1 + 3.125)) <= 1e-9) }
    @Test func opus48() { #expect(abs((PriceTable.cost(model: "claude-opus-4-8", usage: u)!) - (5 + 2.5 + 1 + 3.125)) <= 1e-9) }
    @Test func sonnet55() { #expect(abs((PriceTable.cost(model: "claude-sonnet-5-5", usage: u)!) - (2 + 1 + 0.2 + 1.25)) <= 1e-9) }
    @Test func sonnet5() { #expect(abs((PriceTable.cost(model: "claude-sonnet-5", usage: u)!) - (2 + 1 + 0.4 + 1.25)) <= 1e-9) }
    @Test func haiku45() { #expect(abs((PriceTable.cost(model: "claude-haiku-4-5-20251001", usage: u)!) - (1 + 0.5 + 0.2 + 0.625)) <= 1e-9) }

    @Test func haiku55TiersByPromptSize() {
        let short = Usage(input: 50_000, output: 10_000, cacheRead: 0, cacheWrite: 0)
        #expect(abs((PriceTable.cost(model: "claude-haiku-5-5", usage: short)!) - (0.05 * 0.10 + 0.01 * 0.50)) <= 1e-9)
        let long = Usage(input: 150_000, output: 10_000, cacheRead: 0, cacheWrite: 0)
        #expect(abs((PriceTable.cost(model: "claude-haiku-5-5", usage: long)!) - (0.15 * 0.50 + 0.01 * 2.50)) <= 1e-9)
        // the prompt size counts cache reads: 60k input plus 50k read is over the line
        let mixed = Usage(input: 60_000, output: 0, cacheRead: 50_000, cacheWrite: 0)
        #expect(abs((PriceTable.cost(model: "claude-haiku-5-5", usage: mixed)!) - (0.06 * 0.50 + 0.05 * 0.05)) <= 1e-9)
    }

    @Test func cacheWriteSplit() {
        let split = Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 1_000_000, cacheWrite5m: 250_000, cacheWrite1h: 750_000)
        #expect(abs((PriceTable.cost(model: "claude-fable-5-1", usage: split)!) - (0.25 * 12.5 + 0.75 * 20)) <= 1e-9)
        let noSplit = Usage(input: 0, output: 0, cacheRead: 0, cacheWrite: 1_000_000)
        #expect(abs((PriceTable.cost(model: "claude-fable-5-1", usage: noSplit)!) - (12.5)) <= 1e-9)
    }

    @Test func unknownIdCountsTokensAndNoCost() {
        #expect(PriceTable.cost(model: "claude-mythos-5-1", usage: u) == nil)
        #expect(u.total == 3_600_000)
        #expect(PriceTable.displayName(forModel: "claude-mythos-5-1") == "Mythos 5.1")
        #expect(PriceTable.displayName(forModel: "something-else") == "something-else")
    }

    @Test func prefixMatchingPrefersTheLongestRow() {
        #expect(PriceTable.row(forModel: "claude-opus-5-5")?.name == "Opus 5.5")
        #expect(PriceTable.row(forModel: "claude-opus-5")?.name == "Opus 5")
        #expect(PriceTable.row(forModel: "claude-opus-5-20260301")?.name == "Opus 5")
        #expect(PriceTable.row(forModel: "claude-opus-5-5-20260301")?.name == "Opus 5.5")
        #expect(PriceTable.row(forModel: "claude-opus-55") == nil)
    }

    @Test func displayNames() {
        #expect(PriceTable.displayName(forModel: "claude-fable-5-1") == "Fable 5.1")
        #expect(PriceTable.displayName(forModel: "claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(PriceTable.displayName(forModel: "claude-opus-5") == "Opus 5")
        #expect(PriceTable.family(forModel: "claude-fable-5-1") == "fable")
    }

    @Test func tableIsDated() {
        #expect(PriceTable.readDate == "2026-10-13")
        #expect(PriceTable.rows.count == 8)
        #expect(PriceTable.rows.filter { !$0.idVerified }.count == 4)
    }
}
