import Foundation

enum OpenCodeWindowKind: String, Codable, CaseIterable, Sendable {
    case rolling5h
    case weekly
    case monthly

    var label: String {
        switch self {
        case .rolling5h: return "5-Hour"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var shortLabel: String {
        switch self {
        case .rolling5h: return "5h"
        case .weekly: return "Week"
        case .monthly: return "Month"
        }
    }

    var defaultLimitUSD: Double {
        switch self {
        case .rolling5h: return 12
        case .weekly: return 30
        case .monthly: return 60
        }
    }
}

struct OpenCodeWindowUsage: Identifiable, Hashable, Sendable {
    var kind: OpenCodeWindowKind
    var usedUSD: Double
    var limitUSD: Double
    var resetsAt: Date?
    var sessionCount: Int

    var id: OpenCodeWindowKind { kind }

    var usedPercent: Double {
        Self.clampedPercent(usedUSD: usedUSD, limitUSD: limitUSD)
    }

    var remainingUSD: Double {
        max(0, limitUSD - usedUSD)
    }

    static func clampedPercent(usedUSD: Double, limitUSD: Double) -> Double {
        guard limitUSD > 0 else { return 0 }
        return Percent.clamp(usedUSD / limitUSD * 100)
    }
}

struct OpenCodeModelUsage: Identifiable, Hashable, Sendable {
    var providerID: String
    var modelID: String
    var sessionCount: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheReadTokens: Int64
    var cacheWriteTokens: Int64
    var costUSD: Double
    var percentOfWindow: Double
    /// True when `costUSD` was derived from tokens (Zen $0 rows).
    var isCostEstimated: Bool = false

    var id: String { "\(providerID)/\(modelID)" }

    var displayName: String {
        OpenCodeCatalog.modelDisplayName(providerID: providerID, modelID: modelID)
    }
}

/// One row in the OpenCode week heatmap (model across 7 UTC week days).
struct OpenCodeHeatmapRow: Identifiable, Hashable, Sendable {
    var providerID: String
    var modelID: String
    /// Cost (or session count fallback) per day index 0…6.
    var dayValues: [Double]

    var id: String { "\(providerID)/\(modelID)" }

    var displayName: String {
        OpenCodeCatalog.modelDisplayName(providerID: providerID, modelID: modelID)
    }

    var weekTotal: Double { dayValues.reduce(0, +) }
}

struct OpenCodeWeekHeatmap: Hashable, Sendable {
    var weekStart: Date
    var dayLabels: [String]
    var rows: [OpenCodeHeatmapRow]

    var maxValue: Double {
        rows.flatMap(\.dayValues).max() ?? 0
    }

    var isEmpty: Bool {
        rows.isEmpty || maxValue <= 0
    }
}

/// One stacked segment inside an hour column.
struct OpenCodeHourSegment: Identifiable, Hashable, Sendable {
    var providerID: String
    var modelID: String
    var costUSD: Double
    var messageCount: Int = 0

    var id: String { "\(providerID)/\(modelID)" }

    var displayName: String {
        OpenCodeCatalog.modelDisplayName(providerID: providerID, modelID: modelID)
    }

    /// Activity weight for Overview: prefer $, fall back so free turns still count.
    var activityWeight: Double {
        if costUSD > 0 { return costUSD }
        return Double(messageCount) * 0.01
    }
}

/// One hour of the local day (0…23), with model cost stacks.
struct OpenCodeHourUsage: Identifiable, Hashable, Sendable {
    var hour: Int
    var segments: [OpenCodeHourSegment]
    var messageCount: Int = 0

    var id: Int { hour }

    var totalUSD: Double {
        segments.reduce(0) { $0 + $1.costUSD }
    }

    var hourLabel: String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case 1..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }
}

struct OpenCodeHourLegendItem: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var providerID: String
    var modelID: String
}

struct OpenCodeDayHourlyUsage: Hashable, Sendable {
    var dayStart: Date
    var hours: [OpenCodeHourUsage] // always 24 entries, hour 0…23
    var legend: [OpenCodeHourLegendItem]

    var maxHourUSD: Double {
        hours.map(\.totalUSD).max() ?? 0
    }

    var isEmpty: Bool {
        maxHourUSD <= 0 && hours.allSatisfy { $0.messageCount == 0 }
    }

    var dayTotalUSD: Double {
        hours.reduce(0) { $0 + $1.totalUSD }
    }

    /// Overview weights: Go/Zen → OpenCode; xAI/Grok-via-harness → Grok; other BYOK excluded.
    func overviewProviderHourWeights() -> (openCode: [Double], grokViaOpenCode: [Double]) {
        var openCode = Array(repeating: 0.0, count: 24)
        var grok = Array(repeating: 0.0, count: 24)
        for hour in hours where (0..<24).contains(hour.hour) {
            for segment in hour.segments {
                let weight = segment.activityWeight
                guard weight > 0 else { continue }
                if OpenCodeLocalStats.planEligibleProvider(segment.providerID) {
                    openCode[hour.hour] += weight
                } else if OpenCodeLocalStats.grokViaOpenCode(
                    providerID: segment.providerID,
                    modelID: segment.modelID
                ) {
                    grok[hour.hour] += weight
                }
            }
        }
        return (openCode, grok)
    }
}

enum OpenCodeCatalog {
    static func providerShortName(_ providerID: String) -> String {
        switch providerID.lowercased() {
        case "opencode-go": return "Go"
        case "opencode": return "Zen"
        case "deepseek": return "DeepSeek"
        case "xai": return "xAI"
        case "openrouter": return "OpenRouter"
        case "nvidia": return "NVIDIA"
        case "alibaba": return "Alibaba"
        case "google": return "Google"
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        default: return providerID
        }
    }

    static func modelDisplayName(providerID: String, modelID: String) -> String {
        "\(providerShortName(providerID)) · \(modelID)"
    }
}

struct OpenCodeSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var fetchedAt: Date
    var windows: [OpenCodeWindowUsage]
    var models: [OpenCodeModelUsage]
    var modelsWindowLabel: String
    var inputTokens: Int64
    var outputTokens: Int64
    var cacheReadTokens: Int64
    var cacheWriteTokens: Int64
    var totalSessions: Int
    var isEstimated: Bool

    init(
        id: UUID = UUID(),
        fetchedAt: Date = Date(),
        windows: [OpenCodeWindowUsage],
        models: [OpenCodeModelUsage],
        modelsWindowLabel: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        cacheWriteTokens: Int64,
        totalSessions: Int,
        isEstimated: Bool = true
    ) {
        self.id = id
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.models = models
        self.modelsWindowLabel = modelsWindowLabel
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalSessions = totalSessions
        self.isEstimated = isEstimated
    }

    /// Menu-bar metric: prefer weekly Go usage (matches Grok’s weekly pool style).
    var primaryUsedPercent: Double {
        windows.first { $0.kind == .weekly }?.usedPercent
            ?? windows.first { $0.kind == .rolling5h }?.usedPercent
            ?? windows.first?.usedPercent
            ?? 0
    }

    static let preview = OpenCodeSnapshot(
        windows: [
            OpenCodeWindowUsage(kind: .rolling5h, usedUSD: 8.6, limitUSD: 12, resetsAt: Date().addingTimeInterval(7200), sessionCount: 14),
            OpenCodeWindowUsage(kind: .weekly, usedUSD: 12.4, limitUSD: 30, resetsAt: Date().addingTimeInterval(86_400 * 3), sessionCount: 41),
            OpenCodeWindowUsage(kind: .monthly, usedUSD: 16.9, limitUSD: 60, resetsAt: Date().addingTimeInterval(86_400 * 17), sessionCount: 120)
        ],
        models: [
            OpenCodeModelUsage(providerID: "opencode-go", modelID: "minimax-m3", sessionCount: 9, inputTokens: 14_200_000, outputTokens: 1_300_000, cacheReadTokens: 512_000_000, cacheWriteTokens: 0, costUSD: 4.1, percentOfWindow: 48),
            OpenCodeModelUsage(providerID: "opencode-go", modelID: "kimi-k3", sessionCount: 3, inputTokens: 8_900_000, outputTokens: 420_000, cacheReadTokens: 301_000_000, cacheWriteTokens: 0, costUSD: 2.6, percentOfWindow: 30)
        ],
        modelsWindowLabel: "All models this week",
        inputTokens: 23_100_000,
        outputTokens: 1_720_000,
        cacheReadTokens: 813_000_000,
        cacheWriteTokens: 0,
        totalSessions: 12
    )
}

enum ModelPalette {
    /// OpenCode Go — matches 5-hour limit bar orange.
    static let goOrange: (red: Double, green: Double, blue: Double, alpha: Double) = (0.90, 0.45, 0.20, 1)
    /// OpenCode Zen — matches weekly limit bar blue.
    static let zenBlue: (red: Double, green: Double, blue: Double, alpha: Double) = (0.55, 0.78, 1.0, 1)

    static let sRGB: [(red: Double, green: Double, blue: Double, alpha: Double)] = [
        (0.55, 0.78, 1.0, 1),
        (0.11, 0.38, 0.82, 1),
        (0.22, 0.32, 0.48, 1),
        (0.40, 0.55, 0.82, 1),
        (0.75, 0.90, 1.0, 1),
        (0.90, 0.45, 0.20, 1),
        (0.20, 0.60, 0.40, 1),
        (0.60, 0.30, 0.70, 1)
    ]

    static func sRGB(for seed: String) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let hash = seed.utf8.reduce(5381) { ($0 &* 33) ^ Int($1) }
        let index = abs(hash) % sRGB.count
        return sRGB[index]
    }

    static func sRGB(forProvider providerID: String, seed: String) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        switch providerID.lowercased() {
        case "opencode-go": return goOrange
        case "opencode": return zenBlue
        default: return sRGB(for: seed)
        }
    }
}
