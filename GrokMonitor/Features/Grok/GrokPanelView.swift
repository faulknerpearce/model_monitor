import SwiftUI

struct GrokPanelView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var poller: UsagePoller
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore

    var openSignIn: () -> Void

    /// 0 = current calendar week; negative = past weeks.
    @State private var weekOffset: Int = 0

    var body: some View {
        if auth.needsSignIn && auth.isSignedIn {
            sessionExpiredHeader
        } else if auth.isSignedIn, let snapshot = poller.snapshot {
            usageHeader(snapshot)
        } else if auth.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                ProviderHeaderLabel(provider: .grok, title: "Weekly SuperGrok Limit")
                Text(poller.isRefreshing ? "Refreshing…" : (poller.lastError ?? "Signed in — waiting for usage data."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if poller.lastError != nil {
                    Button("Sign In Again…") { openSignIn() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            signedOutHeader
        }
    }

    private var sessionExpiredHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeaderLabel(provider: .grok, title: "Weekly SuperGrok Limit")
            Text(poller.lastError ?? "Session expired. Sign in again to load usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In Again…") { openSignIn() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usageHeader(_ snapshot: WeeklyUsageSnapshot) -> some View {
        let products = settings.filteredProducts(from: snapshot)
        let week = DailyUsageBuilder.week(
            history: history.recent.reversed(),
            current: snapshot,
            serverDaily: snapshot.dailySeries,
            weekOffset: weekOffset,
            resetsAt: snapshot.resetsAt
        )

        VStack(alignment: .leading, spacing: 10) {
            ProviderHeaderLabel(provider: .grok, title: "Weekly SuperGrok Limit")

            Text("\(Int(snapshot.usedPercent.rounded()))% used · \(Int(snapshot.remainingPercent.rounded()))% remaining")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SegmentedUsageBar(products: products, height: 10)

            VStack(spacing: 6) {
                ForEach(products) { product in
                    CategoryRow(product: product)
                }
            }
            .padding(.top, 4)

            if let credits = snapshot.extraCreditsBalance, credits > 0 {
                HStack {
                    Text("Extra Usage Credits")
                    Spacer()
                    Text(credits as NSDecimalNumber, formatter: Self.currencyFormatter)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }

            Divider().padding(.vertical, 2)

            DailyUsageChartView(
                week: week,
                onPreviousWeek: { weekOffset -= 1 },
                onNextWeek: { weekOffset = min(0, weekOffset + 1) },
                canGoNext: weekOffset < 0
            )

            if let resetsAt = snapshot.resetsAt, week.resetCaption == nil {
                Text("Resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            if let error = poller.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeaderLabel(provider: .grok, title: "Weekly SuperGrok Limit")
            Text("Sign in to load your usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In…") { openSignIn() }
                .keyboardShortcut("s", modifiers: [.command])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}
