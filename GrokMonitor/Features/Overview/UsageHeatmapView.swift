import SwiftUI

/// Shared grid model for GitHub-style contribution squares.
struct UsageHeatmapGrid: Hashable, Sendable {
    struct Row: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var color: (red: Double, green: Double, blue: Double)
        var dayValues: [Double]

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id && lhs.label == rhs.label && lhs.dayValues == rhs.dayValues
                && lhs.color.red == rhs.color.red
                && lhs.color.green == rhs.color.green
                && lhs.color.blue == rhs.color.blue
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(label)
            hasher.combine(dayValues)
            hasher.combine(color.red)
            hasher.combine(color.green)
            hasher.combine(color.blue)
        }
    }

    var dayLabels: [String]
    var rows: [Row]

    var maxValue: Double {
        rows.flatMap(\.dayValues).max() ?? 0
    }

    var isEmpty: Bool {
        rows.isEmpty || maxValue <= 0
    }

    static func fromOpenCode(_ heat: OpenCodeWeekHeatmap) -> UsageHeatmapGrid {
        UsageHeatmapGrid(
            dayLabels: heat.dayLabels,
            rows: heat.rows.map { row in
                let c = ModelPalette.sRGB(forProvider: row.providerID, seed: row.id)
                return Row(
                    id: row.id,
                    label: shortModelLabel(row.modelID),
                    color: (c.red, c.green, c.blue),
                    dayValues: row.dayValues
                )
            }
        )
    }

    static func fromGrok(week: DailyUsageWeek, visibleProductIDs: Set<String>) -> UsageHeatmapGrid {
        let dayLabels = week.days.map(\.weekdaySymbol)
        var productOrder: [String] = []
        var seen = Set<String>()
        for day in week.days {
            for segment in day.segments {
                let id = segment.productID.lowercased()
                guard visibleProductIDs.contains(id) || visibleProductIDs.isEmpty else { continue }
                if seen.insert(id).inserted {
                    productOrder.append(id)
                }
            }
        }
        productOrder = ProductCatalog.displayOrder.filter { productOrder.contains($0) }
            + productOrder.filter { !ProductCatalog.displayOrder.contains($0) }

        let rows: [Row] = productOrder.compactMap { productID in
            let values = week.days.map { day in
                day.segments
                    .filter { $0.productID.lowercased() == productID }
                    .reduce(0) { $0 + $1.percentOfWeekly }
            }
            guard values.contains(where: { $0 > 0.05 }) else { return nil }
            let token = ProductColor.from(productID: productID)
            return Row(
                id: productID,
                label: ProductCatalog.shortName(for: productID),
                color: (token.sRGB.red, token.sRGB.green, token.sRGB.blue),
                dayValues: values
            )
        }
        return UsageHeatmapGrid(dayLabels: dayLabels, rows: rows)
    }

    private static func shortModelLabel(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 14 { return trimmed }
        return String(trimmed.prefix(12)) + "…"
    }
}

struct UsageHeatmapView: View {
    let title: String
    let grid: UsageHeatmapGrid?
    let emptyMessage: String

    private let cellSize: CGFloat = 11
    private let cellGap: CGFloat = 2
    private let labelWidth: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if let grid, !grid.isEmpty {
                gridBody(grid)
            } else {
                Text(emptyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gridBody(_ grid: UsageHeatmapGrid) -> some View {
        let maxValue = max(grid.maxValue, 0.0001)
        return VStack(alignment: .leading, spacing: cellGap) {
            HStack(spacing: cellGap) {
                Color.clear.frame(width: labelWidth, height: 10)
                ForEach(Array(grid.dayLabels.enumerated()), id: \.offset) { _, label in
                    Text(String(label.prefix(1)))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: cellSize, height: 10)
                }
            }

            ForEach(grid.rows) { row in
                HStack(spacing: cellGap) {
                    Text(row.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(Array(row.dayValues.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(cellColor(base: row.color, value: value, maxValue: maxValue))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func cellColor(
        base: (red: Double, green: Double, blue: Double),
        value: Double,
        maxValue: Double
    ) -> Color {
        guard value > 0 else {
            return Color.primary.opacity(0.08)
        }
        let intensity = min(1, max(0.18, value / maxValue))
        return Color(
            red: base.red,
            green: base.green,
            blue: base.blue
        ).opacity(0.25 + 0.75 * intensity)
    }
}
