import Foundation

/// One hour’s Grok vs OpenCode activity share for the Overview chart.
struct ProviderHourUsage: Identifiable, Hashable, Sendable {
    var hour: Int
    /// 0…100 share of this hour’s combined activity.
    var grokSharePercent: Double
    /// 0…100 share of this hour’s combined activity.
    var openCodeSharePercent: Double
    /// Relative activity used for bar height.
    var activity: Double
    /// Dollar-ish amount for peak labels (OpenCode / harness $ for this hour).
    var costUSD: Double

    var id: Int { hour }

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

    /// Merge Grok percent-point deltas with OpenCode activity weights into hourly shares.
    ///
    /// Each provider is first normalized to its own day total, then the hour’s stack
    /// is the share of those normalized intensities (so $ and % points can combine).
    /// `hourCostUSD` is used only for peak `$` labels (typically OpenCode + Grok-via-harness $).
    static func build(
        dayStart: Date,
        grokHourWeights: [Double],
        openCodeHourWeights: [Double],
        hourCostUSD: [Double]? = nil
    ) -> ProviderDayHourlyUsage {
        precondition(grokHourWeights.count == 24)
        precondition(openCodeHourWeights.count == 24)
        let costs = hourCostUSD ?? openCodeHourWeights
        precondition(costs.count == 24)

        let dayGrok = grokHourWeights.reduce(0, +)
        let dayOpenCode = openCodeHourWeights.reduce(0, +)

        let hours: [ProviderHourUsage] = (0..<24).map { hour in
            let grokNorm = dayGrok > 0 ? grokHourWeights[hour] / dayGrok : 0
            let openNorm = dayOpenCode > 0 ? openCodeHourWeights[hour] / dayOpenCode : 0
            let activity = grokNorm + openNorm
            let grokShare = activity > 0 ? grokNorm / activity * 100 : 0
            let openShare = activity > 0 ? openNorm / activity * 100 : 0
            return ProviderHourUsage(
                hour: hour,
                grokSharePercent: grokShare,
                openCodeSharePercent: openShare,
                activity: activity,
                costUSD: max(0, costs[hour])
            )
        }

        return ProviderDayHourlyUsage(dayStart: dayStart, hours: hours)
    }
}
