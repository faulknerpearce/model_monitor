import SwiftUI

struct OpenCodePanelView: View {
    @ObservedObject var poller: OpenCodeUsagePoller
    @ObservedObject var auth: OpenCodeAuthSession
    var openSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if auth.needsSignIn && poller.snapshot == nil {
                signedOut
            } else if let snapshot = poller.snapshot {
                HStack {
                    ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
                    Spacer()
                    if let source = poller.dataSourceLabel {
                        Text(source)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(snapshot.isEstimated ? Color.orange : Color.secondary)
                    }
                }

                ForEach(snapshot.windows) { window in
                    OpenCodeLimitBar(window: window)
                }

                if snapshot.isEstimated {
                    Text("Estimated from local sessions — sign in for console accuracy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if !snapshot.models.isEmpty {
                    Divider().padding(.vertical, 2)

                    OpenCodeModelsSection(
                        models: snapshot.models,
                        sectionLabel: snapshot.modelsWindowLabel,
                        weekHeatmap: poller.weekHeatmap
                    )
                }

                if auth.needsSignIn || poller.lastError != nil {
                    if let err = poller.lastError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button(auth.needsSignIn ? "Sign In to OpenCode…" : "Sign In Again…") {
                        openSignIn()
                    }
                    .font(.system(size: 12))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
                    Text(poller.isRefreshing ? "Refreshing…" : (poller.lastError ?? "No usage data yet."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if auth.needsSignIn {
                        Button("Sign In to OpenCode…") { openSignIn() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
            Text("Sign in to the OpenCode console to load official rolling, weekly, and monthly usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In to OpenCode…") { openSignIn() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact ranked list of Go/Zen models with GitHub-style week contribution strips.
struct OpenCodeModelsSection: View {
    let models: [OpenCodeModelUsage]
    let sectionLabel: String
    var weekHeatmap: OpenCodeWeekHeatmap?

    private let maxModels = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sectionLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            let weekMax = max(weekHeatmap?.maxValue ?? 0, 0.01)
            let dayLabels = weekHeatmap?.dayLabels ?? []

            ForEach(Array(models.prefix(maxModels).enumerated()), id: \.element.id) { index, model in
                OpenCodeModelWeekRow(
                    model: model,
                    dayValues: dayValues(for: model),
                    dayLabels: dayLabels,
                    weekMaxValue: weekMax
                )
                if index < min(models.count, maxModels) - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
    }

    private func dayValues(for model: OpenCodeModelUsage) -> [Double] {
        guard let row = weekHeatmap?.rows.first(where: { $0.id == model.id }) else {
            return []
        }
        return row.dayValues
    }
}

struct OpenCodeModelWeekRow: View {
    let model: OpenCodeModelUsage
    var dayValues: [Double] = []
    var dayLabels: [String] = []
    var weekMaxValue: Double = 0.01

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 2

    private var accent: Color {
        let c = ModelPalette.sRGB(forProvider: model.providerID, seed: model.id)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var providerTag: String {
        OpenCodeCatalog.providerShortName(model.providerID)
    }

    private var costLabel: String {
        let formatted = Format.usdCurrency.string(from: NSNumber(value: model.costUSD)) ?? "$0"
        if model.isCostEstimated {
            return "~\(formatted)"
        }
        return formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(providerTag)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(model.modelID)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(costLabel)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if !dayValues.isEmpty, dayValues.contains(where: { $0 > 0 }) {
                    contributionStrip
                } else if model.sessionCount > 0 {
                    Text("\(model.sessionCount) session\(model.sessionCount == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Color.clear.frame(height: cellSize)
                }
                Spacer(minLength: 0)
                Text("\(Int(model.percentOfWindow.rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var contributionStrip: some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<min(7, dayValues.count), id: \.self) { day in
                let value = dayValues[day]
                let level = Self.intensityLevel(value: value, maxValue: weekMaxValue)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.cellFill(accent: accent, level: level))
                    .frame(width: cellSize, height: cellSize)
                    .help(cellHelp(dayIndex: day, value: value))
            }
        }
    }

    private func cellHelp(dayIndex: Int, value: Double) -> String {
        let day = dayLabels.indices.contains(dayIndex) ? dayLabels[dayIndex] : "Day \(dayIndex + 1)"
        guard value > 0 else { return "\(model.modelID) · \(day): none" }
        let amount: String
        if value >= 1 {
            amount = String(format: "$%.1f", value)
        } else {
            amount = String(format: "$%.2f", value)
        }
        return "\(model.modelID) · \(day): \(amount)"
    }

    /// GitHub-like 0…4 intensity buckets from day value vs week max.
    static func intensityLevel(value: Double, maxValue: Double) -> Int {
        guard value > 0, maxValue > 0 else { return 0 }
        let ratio = value / maxValue
        if ratio < 0.15 { return 1 }
        if ratio < 0.35 { return 2 }
        if ratio < 0.65 { return 3 }
        return 4
    }

    static func cellFill(accent: Color, level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.08)
        case 1: return accent.opacity(0.28)
        case 2: return accent.opacity(0.48)
        case 3: return accent.opacity(0.72)
        default: return accent.opacity(0.95)
        }
    }
}

/// Kept for previews / any remaining call sites.
struct OpenCodeModelRow: View {
    let model: OpenCodeModelUsage

    var body: some View {
        OpenCodeModelWeekRow(model: model)
    }
}
