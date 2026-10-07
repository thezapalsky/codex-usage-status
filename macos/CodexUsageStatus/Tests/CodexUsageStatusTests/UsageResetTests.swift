import Foundation
import XCTest
@testable import CodexUsageStatus

final class UsageResetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let locale = Locale(identifier: "en_GB")

    func testResetInfoIsHiddenWhileBothWindowsHaveQuota() throws {
        let usage = try summary(fiveHourRemaining: 1, weeklyRemaining: 50, fiveHourReset: date(day: 7, hour: 15))
        XCTAssertTrue(usage.exhaustedResets.isEmpty)
        XCTAssertEqual(usage.resetStatusText(now: date(day: 7, hour: 12), calendar: calendar, locale: locale), "")
    }

    func testOnlyExhaustedFiveHourWindowShowsTodayTime() throws {
        let usage = try summary(fiveHourRemaining: 0, weeklyRemaining: 50, fiveHourReset: date(day: 7, hour: 15))
        XCTAssertEqual(usage.exhaustedResets.map(\.label), ["5h"])
        XCTAssertEqual(usage.resetStatusText(now: date(day: 7, hour: 12), calendar: calendar, locale: locale), "5h ↻ 15:00")
    }

    func testOnlyExhaustedWeeklyWindowIncludesResetDay() throws {
        let usage = try summary(fiveHourRemaining: 50, weeklyRemaining: 0, weeklyReset: date(day: 9, hour: 9))
        XCTAssertEqual(usage.exhaustedResets.map(\.label), ["7d"])
        let text = usage.resetStatusText(now: date(day: 7, hour: 12), calendar: calendar, locale: locale)
        XCTAssertTrue(text.hasPrefix("7d ↻ "))
        XCTAssertTrue(text.contains("Fri"))
        XCTAssertTrue(text.contains("09:00"))
    }

    func testBothExhaustedWindowsShowTheirOwnReset() throws {
        let usage = try summary(
            fiveHourRemaining: 0,
            weeklyRemaining: 0,
            fiveHourReset: date(day: 7, hour: 15),
            weeklyReset: date(day: 9, hour: 9)
        )
        XCTAssertEqual(usage.exhaustedResets.map(\.label), ["5h", "7d"])
        let text = usage.resetStatusText(now: date(day: 7, hour: 12), calendar: calendar, locale: locale)
        XCTAssertTrue(text.hasPrefix("5h ↻ 15:00 · 7d ↻ "))
        XCTAssertTrue(text.contains("Fri"))
    }

    func testMissingTimestampDoesNotInventResetTime() throws {
        let usage = try summary(fiveHourRemaining: 0, weeklyRemaining: 50)
        let now = date(day: 7, hour: 12)
        XCTAssertEqual(usage.resetStatusText(now: now, calendar: calendar, locale: locale), "5h ↻ ?")
        XCTAssertTrue(usage.exhaustedResets[0].menuText(formatter: DateFormatter(), now: now).contains("reset time unavailable"))
    }

    func testPastTimestampIsPendingInsteadOfAFalseFutureReset() throws {
        let usage = try summary(fiveHourRemaining: 0, weeklyRemaining: 50, fiveHourReset: date(day: 7, hour: 11))
        let now = date(day: 7, hour: 12)
        XCTAssertEqual(usage.resetStatusText(now: now, calendar: calendar, locale: locale), "5h ↻ pending")
        XCTAssertTrue(usage.exhaustedResets[0].menuText(formatter: DateFormatter(), now: now).contains("waiting for updated reset time"))
    }

    func testResetTimeUsesTheLocalTimeZone() throws {
        let usage = try summary(fiveHourRemaining: 0, weeklyRemaining: 50, fiveHourReset: date(day: 7, hour: 15))
        var warsaw = calendar
        warsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        XCTAssertEqual(usage.resetStatusText(now: date(day: 7, hour: 12), calendar: warsaw, locale: locale), "5h ↻ 17:00")
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func summary(
        fiveHourRemaining: Int,
        weeklyRemaining: Int,
        fiveHourReset: Date? = nil,
        weeklyReset: Date? = nil
    ) throws -> UsageSummary {
        try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: Double(100 - fiveHourRemaining),
                    windowDurationMins: 300,
                    resetsAt: fiveHourReset?.timeIntervalSince1970
                ),
                secondary: RateLimitWindow(
                    usedPercent: Double(100 - weeklyRemaining),
                    windowDurationMins: 10080,
                    resetsAt: weeklyReset?.timeIntervalSince1970
                ),
                planType: "plus"
            ),
            rateLimitsByLimitId: nil
        ))
    }
}
