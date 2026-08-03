import SwiftUI

struct OverviewPanelView: View {
    @ObservedObject var grokPoller: UsagePoller
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var grokAuth: AuthSessionService
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore

    var openGrokSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void

    private static let grokRingColor = Color(red: 0.11, green: 0.38, blue: 0.82)
    private static let openCodeRingColor = Color(red: 0.90, green: 0.45, blue: 0.20)

    @State private var grokHeatmapCache: (key: String, grid: UsageHeatmapGrid?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly overview")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 12) {
                UsageRingView(
                    title: "Grok",
                    percent: grokPoller.snapshot?.usedPercent,
                    color: Self.grokRingColor,
                    emptyCaption: grokAuth.isSignedIn ? "…" : "—"
                )
                UsageRingView(
                    title: "OpenCode",
                    percent: openCodePoller.snapshot?.primaryUsedPercent,
                    color: Self.openCodeRingColor,
                    emptyCaption: openCodeAuth.isSignedIn || openCodePoller.snapshot != nil ? "…" : "—"
                )
            }

            signInHints

            Divider().padding(.vertical, 2)

            Text("This week")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                UsageHeatmapView(
                    title: "Grok · products",
                    grid: grokHeatmap,
                    emptyMessage: grokEmptyMessage
                )
                UsageHeatmapView(
                    title: "OpenCode · models",
                    grid: openCodeHeatmap,
                    emptyMessage: openCodeEmptyMessage
                )
            }
        }
    }

    @ViewBuilder
    private var signInHints: some View {
        if !grokAuth.isSignedIn || grokAuth.needsSignIn {
            Button("Sign In to Grok…") { openGrokSignIn() }
                .font(.system(size: 11))
        }
        if openCodeAuth.needsSignIn && openCodePoller.snapshot == nil {
            Button("Sign In to OpenCode…") { openOpenCodeSignIn() }
                .font(.system(size: 11))
        }
    }

    private var grokHeatmap: UsageHeatmapGrid? {
        let snap = grokPoller.snapshot
        let last = history.recent.first
        let key = "\(last?.id.uuidString ?? "")-\(last?.fetchedAt.timeIntervalSince1970 ?? 0)" +
            "-\(snap?.id.uuidString ?? "")-\(snap?.dailySeries.count ?? 0)" +
            "-\(snap?.resetsAt?.timeIntervalSince1970 ?? 0)" +
            "-\(settings.visibleProductIDs.sorted().joined(separator: ","))"
        if let cached = grokHeatmapCache, cached.key == key {
            return cached.grid
        }
        let week = DailyUsageBuilder.week(
            history: history.recent.reversed(),
            current: snap,
            serverDaily: snap?.dailySeries ?? [],
            weekOffset: 0,
            resetsAt: snap?.resetsAt
        )
        let grid = UsageHeatmapGrid.fromGrok(week: week, visibleProductIDs: settings.visibleProductIDs)
        let result = grid.isEmpty ? nil : grid
        grokHeatmapCache = (key, result)
        return result
    }

    private var openCodeHeatmap: UsageHeatmapGrid? {
        guard let heat = openCodePoller.weekHeatmap, !heat.isEmpty else { return nil }
        return UsageHeatmapGrid.fromOpenCode(heat)
    }

    private var grokEmptyMessage: String {
        if !grokAuth.isSignedIn {
            return "Sign in to track Grok days."
        }
        return "Need a few daily samples."
    }

    private var openCodeEmptyMessage: String {
        if openCodePoller.weekHeatmap == nil {
            return "No local OpenCode sessions."
        }
        return "No model use this week."
    }
}
