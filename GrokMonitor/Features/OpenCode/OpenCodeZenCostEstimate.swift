import Foundation

/// Token-based USD estimates for OpenCode Zen when the local DB records `$0`
/// (common for free-tier models that still burn tokens).
enum OpenCodeZenCostEstimate {
    /// Rates per 1M tokens (input, output, cacheRead, cacheWrite).
    private struct Rates {
        var input: Double
        var output: Double
        var cacheRead: Double
        var cacheWrite: Double
    }

    /// Official Zen pricing (and paid peers for `*-free` models). Unknown models
    /// fall back to a modest generic rate so usage still surfaces as an estimate.
    private static let ratesByModelID: [String: Rates] = [
        // Free → paid peer rates (value of usage, not charged).
        "deepseek-v4-flash-free": Rates(input: 0.14, output: 0.28, cacheRead: 0.028, cacheWrite: 0),
        "nemotron-3-ultra-free": Rates(input: 0.20, output: 0.80, cacheRead: 0.02, cacheWrite: 0),
        "mimo-v2.5-free": Rates(input: 0.20, output: 0.80, cacheRead: 0.02, cacheWrite: 0),
        "laguna-s-2.1-free": Rates(input: 0.20, output: 0.80, cacheRead: 0.02, cacheWrite: 0),
        "ling-3.0-flash-free": Rates(input: 0.14, output: 0.28, cacheRead: 0.028, cacheWrite: 0),
        "north-mini-code-free": Rates(input: 0.20, output: 0.80, cacheRead: 0.02, cacheWrite: 0),
        "big-pickle": Rates(input: 0.30, output: 1.20, cacheRead: 0.06, cacheWrite: 0),
        // Paid Zen catalogue (subset; unknown IDs use fallback).
        "deepseek-v4-flash": Rates(input: 0.14, output: 0.28, cacheRead: 0.028, cacheWrite: 0),
        "deepseek-v4-pro": Rates(input: 1.74, output: 3.48, cacheRead: 0.145, cacheWrite: 0),
        "minimax-m3": Rates(input: 0.30, output: 1.20, cacheRead: 0.06, cacheWrite: 0),
        "gpt-5.6-luna": Rates(input: 0.20, output: 1.20, cacheRead: 0.02, cacheWrite: 0.25),
        "kimi-k3": Rates(input: 3.00, output: 15.00, cacheRead: 0.30, cacheWrite: 0),
    ]

    private static let fallback = Rates(input: 0.50, output: 1.50, cacheRead: 0.05, cacheWrite: 0)

    static func isZenProvider(_ providerID: String) -> Bool {
        providerID.lowercased() == "opencode"
    }

    /// Prefer recorded cost; otherwise estimate Zen spend from tokens.
    static func billableCostUSD(
        providerID: String,
        modelID: String,
        recordedCostUSD: Double,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheWriteTokens: Int64
    ) -> (cost: Double, isEstimated: Bool) {
        if recordedCostUSD > 0 {
            return (recordedCostUSD, false)
        }
        guard isZenProvider(providerID) else {
            return (0, false)
        }
        let tokens = inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
        guard tokens > 0 else {
            return (0, false)
        }
        let estimated = estimate(
            modelID: modelID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )
        return (estimated, estimated > 0)
    }

    static func estimate(
        modelID: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheWriteTokens: Int64
    ) -> Double {
        let rates = ratesByModelID[modelID.lowercased()] ?? fallback
        let perMillion = 1_000_000.0
        return rates.input * Double(inputTokens) / perMillion
            + rates.output * Double(outputTokens) / perMillion
            + rates.cacheRead * Double(cacheReadTokens) / perMillion
            + rates.cacheWrite * Double(cacheWriteTokens) / perMillion
    }
}
