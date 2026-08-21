import Combine
import Foundation
import os

@MainActor
final class ClaudeUsagePoller: ObservableObject, ProviderUsagePoller {
    @Published private(set) var snapshot: ClaudeSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshedAt: Date?
    /// 7 rolling daily bars: % of the weekly pool burned per calendar day.
    @Published private(set) var dailyBudgetDays: [DailyBudgetDay]?
    @Published var menuIsOpen = false

    private let settings: AppSettings
    private let auth: ClaudeAuthSession
    private let hourly: HourlyDeltaActivityStore
    private let daily: DailyQuotaDeltaStore
    private let logger = Logger(category: "Claude")

    private lazy var loop = PollingLoop(
        interval: { [weak self] in self?.currentInterval() },
        refresh: { [weak self] in await self?.refreshNow() }
    )

    init(settings: AppSettings, auth: ClaudeAuthSession, hourly: HourlyDeltaActivityStore, daily: DailyQuotaDeltaStore) {
        self.settings = settings
        self.auth = auth
        self.hourly = hourly
        self.daily = daily
    }

    func start() {
        loop.start()
    }

    func stop() {
        loop.stop()
    }

    func clearSnapshot() {
        snapshot = nil
        dailyBudgetDays = nil
        lastError = nil
    }

    func refreshNow() async {
        guard settings.needsClaudePolling else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let cookieHeader = auth.cookieHeader(), !cookieHeader.isEmpty else {
            auth.needsSignIn = true
            if snapshot == nil {
                lastError = "Sign in to Claude to load usage."
            }
            return
        }

        let client = ClaudeUsageClient(cookieHeader: cookieHeader)
        do {
            let (response, fetchedAt) = try await client.fetchUsage()
            guard !Task.isCancelled, auth.isSignedIn, !auth.needsSignIn else { return }
            snapshot = ClaudeSnapshot(
                fetchedAt: fetchedAt,
                fiveHour: response.fiveHour,
                sevenDay: response.sevenDay,
                accountEmail: auth.accountEmail
            )
            lastError = nil
            lastRefreshedAt = Date()
            auth.needsSignIn = false
            if let percent = response.fiveHour?.usedPercent {
                hourly.record(usedPercent: percent, at: fetchedAt)
                daily.record(windowUsedPercent: percent, at: fetchedAt)
                logger.info("Claude refresh: 5h \(percent, format: .fixed(precision: 1))% used")
            }
            dailyBudgetDays = Self.buildDailyBudgetDays(spentByDay: daily.spentByDay, now: fetchedAt)
        } catch let error as ClaudeUsageError {
            let usageError = error.usageError
            switch usageError {
            case .unauthorized, .notSignedIn:
                auth.markSessionInvalid(reason: error.localizedDescription)
            default:
                break
            }
            if snapshot == nil {
                lastError = error.localizedDescription
            }
            logger.error("Claude refresh failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            if snapshot == nil {
                lastError = error.localizedDescription
            }
            logger.error("Claude refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func currentInterval() -> TimeInterval {
        PollInterval.seconds(menuIsOpen: menuIsOpen, settings: settings)
    }

    /// 7 rolling daily bars ending today. The 5-hour window can be used up
    /// ~4–5 times per day, so the daily budget is one full window (100%).
    static func buildDailyBudgetDays(spentByDay: [Date: Double], now: Date = Date()) -> [DailyBudgetDay] {
        DailyBudget.buildRolling7Days(
            limitUSD: 700,
            daysInPeriod: 7,
            spentByDay: spentByDay,
            now: now
        )
    }
}
