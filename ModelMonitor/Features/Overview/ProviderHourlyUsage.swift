import Foundation

/// One hour's Grok / OpenCode Go / OpenCode Zen / Cursor quota consumption.
struct ProviderHourUsage: Identifiable, Hashable, Sendable {
    var hour: Int
    /// 0…100 share of this hour’s combined activity.
    var grokSharePercent: Double
    /// 0…100 share of this hour's combined activity.
    var openCodeGoSharePercent: Double
    /// 0…100 share of this hour's combined activity.
    var openCodeZenSharePercent: Double
    /// 0…100 share of this hour’s combined activity.
    var cursorSharePercent: Double
    /// Percentage points of provider quota consumed during this hour.
    var activity: Double
    /// Dollar-ish amount for peak labels (OpenCode / harness $ for this hour).
    var costUSD: Double

    var id: Int { hour }

    var openCodeSharePercent: Double {
        openCodeGoSharePercent + openCodeZenSharePercent
    }

    var hourLabel: String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case 1..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }

    var hasActivity: Bool { activity > 0 }
}

struct ProviderDayHourlyUsage: Hashable, Sendable {
    var dayStart: Date
    var hours: [ProviderHourUsage] // 24 entries

    var maxActivity: Double {
        hours.map(\.activity).max() ?? 0
    }

    var isEmpty: Bool {
        maxActivity <= 0
    }

    /// Merge hourly quota-consumption deltas into provider shares.
    ///
    /// All hourly inputs are percentage-point deltas against the provider's own quota,
    /// which makes the combined height comparable without daily re-normalization.
    /// `hourCostUSD` is used only for peak `$` labels.
    static func build(
        dayStart: Date,
        grokHourWeights: [Double],
        openCodeGoHourWeights: [Double],
        openCodeZenHourWeights: [Double],
        cursorHourWeights: [Double] = Array(repeating: 0, count: 24),
        hourCostUSD: [Double]? = nil
    ) -> ProviderDayHourlyUsage {
        precondition(grokHourWeights.count == 24)
        precondition(openCodeGoHourWeights.count == 24)
        precondition(openCodeZenHourWeights.count == 24)
        precondition(cursorHourWeights.count == 24)
        let costs = hourCostUSD ?? Array(repeating: 0.0, count: 24)
        precondition(costs.count == 24)

        let hours: [ProviderHourUsage] = (0..<24).map { hour in
            let grokDelta = max(0, grokHourWeights[hour])
            let openGoDelta = max(0, openCodeGoHourWeights[hour])
            let openZenDelta = max(0, openCodeZenHourWeights[hour])
            let cursorDelta = max(0, cursorHourWeights[hour])
            let activity = grokDelta + openGoDelta + openZenDelta + cursorDelta
            let grokShare = activity > 0 ? grokDelta / activity * 100 : 0
            let openGoShare = activity > 0 ? openGoDelta / activity * 100 : 0
            let openZenShare = activity > 0 ? openZenDelta / activity * 100 : 0
            let cursorShare = activity > 0 ? cursorDelta / activity * 100 : 0
            return ProviderHourUsage(
                hour: hour,
                grokSharePercent: grokShare,
                openCodeGoSharePercent: openGoShare,
                openCodeZenSharePercent: openZenShare,
                cursorSharePercent: cursorShare,
                activity: activity,
                costUSD: max(0, costs[hour])
            )
        }

        return ProviderDayHourlyUsage(dayStart: dayStart, hours: hours)
    }
}
