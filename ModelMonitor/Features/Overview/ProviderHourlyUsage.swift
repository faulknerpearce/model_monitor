import Foundation

/// One hour's Grok / OpenCode Go / OpenCode Zen / Cursor activity share.
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
    /// Relative activity used for bar height.
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

    /// Merge provider activity weights into hourly shares.
    ///
    /// Each provider is first normalized to its own day total, then the hour’s stack
    /// is the share of those normalized intensities (so $ and % points can combine).
    /// `hourCostUSD` is used only for peak `$` labels (typically OpenCode + Grok-via-harness $).
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
        let costs = hourCostUSD ?? zip(openCodeGoHourWeights, openCodeZenHourWeights).map(+)
        precondition(costs.count == 24)

        let dayGrok = grokHourWeights.reduce(0, +)
        let dayOpenCodeGo = openCodeGoHourWeights.reduce(0, +)
        let dayOpenCodeZen = openCodeZenHourWeights.reduce(0, +)
        let dayOpenCode = dayOpenCodeGo + dayOpenCodeZen
        let dayCursor = cursorHourWeights.reduce(0, +)

        let hours: [ProviderHourUsage] = (0..<24).map { hour in
            let grokNorm = dayGrok > 0 ? grokHourWeights[hour] / dayGrok : 0
            let openCodeWeight = openCodeGoHourWeights[hour] + openCodeZenHourWeights[hour]
            let openNorm = dayOpenCode > 0 ? openCodeWeight / dayOpenCode : 0
            let openGoFraction = openCodeWeight > 0 ? openCodeGoHourWeights[hour] / openCodeWeight : 0
            let openZenFraction = openCodeWeight > 0 ? openCodeZenHourWeights[hour] / openCodeWeight : 0
            let openGoNorm = openNorm * openGoFraction
            let openZenNorm = openNorm * openZenFraction
            let cursorNorm = dayCursor > 0 ? cursorHourWeights[hour] / dayCursor : 0
            let activity = grokNorm + openGoNorm + openZenNorm + cursorNorm
            let grokShare = activity > 0 ? grokNorm / activity * 100 : 0
            let openGoShare = activity > 0 ? openGoNorm / activity * 100 : 0
            let openZenShare = activity > 0 ? openZenNorm / activity * 100 : 0
            let cursorShare = activity > 0 ? cursorNorm / activity * 100 : 0
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
