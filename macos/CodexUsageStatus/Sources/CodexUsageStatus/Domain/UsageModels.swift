import Foundation

struct RateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: TimeInterval?
}

struct UsageSummary: Sendable {
    let planType: String?
    let fiveHour: UsageWindow
    let weekly: UsageWindow
    let reserveWeekly: UsageWindow?

    init(response: RateLimitsResponse) throws {
        let snapshot = response.rateLimitsByLimitId?["codex"]
            ?? response.rateLimits
            ?? response.rateLimitsByLimitId?.values.first

        guard let snapshot else {
            throw FetchError.invalidOutput
        }

        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }.map(UsageWindow.init)
        let fiveHour = windows.first { approximately($0.windowDurationMins, 300) } ?? windows.first
        let weekly = windows.first { approximately($0.windowDurationMins, 10080) } ?? windows.dropFirst().first

        guard let fiveHour, let weekly else {
            throw FetchError.invalidOutput
        }

        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly

        if let reserveSnapshot = response.rateLimitsByLimitId?["gpt-reserve-limit"] {
            let reserveWindows = [reserveSnapshot.primary, reserveSnapshot.secondary]
                .compactMap { $0 }
                .map(UsageWindow.init)
            self.reserveWeekly = reserveWindows.first { approximately($0.windowDurationMins, 10080) }
                ?? reserveWindows.first
        } else {
            self.reserveWeekly = nil
        }
    }

    var menuTitle: String {
        var parts = [
            "5h \(fiveHour.remainingPercent)%",
            "7d \(weekly.remainingPercent)%",
        ]
        if let reserveWeekly {
            parts.append("gpt-reserve \(reserveWeekly.remainingPercent)%")
        }
        return parts.joined(separator: " ")
    }

    var verboseTitle: String {
        var parts = [
            "Codex usage: 5-hour \(fiveHour.remainingPercent)%",
            "weekly \(weekly.remainingPercent)%",
        ]
        if let reserveWeekly {
            parts.append("GPT reserve weekly \(reserveWeekly.remainingPercent)%")
        }
        return parts.joined(separator: " · ")
    }

    var exhaustedResets: [UsageResetInfo] {
        var resets: [UsageResetInfo] = []
        if fiveHour.remainingPercent == 0 {
            resets.append(UsageResetInfo(label: "5h", title: "5-hour", resetsAt: fiveHour.resetsAt))
        }
        if weekly.remainingPercent == 0 {
            resets.append(UsageResetInfo(label: "7d", title: "Weekly", resetsAt: weekly.resetsAt))
        }
        return resets
    }

    func resetStatusText(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        exhaustedResets.map { $0.compactText(now: now, calendar: calendar, locale: locale) }
            .joined(separator: " · ")
    }

    func tooltip(formatter: DateFormatter) -> String {
        let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        var lines = [
            "Codex usage",
            "5-hour remaining: \(fiveHour.remainingPercent)% · resets \(fiveHourReset)",
            "Weekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)",
        ]
        if let reserveWeekly {
            let reserveReset = reserveWeekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
            lines.append("GPT reserve weekly remaining: \(reserveWeekly.remainingPercent)% · resets \(reserveReset)")
        }
        return lines.joined(separator: "\n")
    }
}

struct UsageResetInfo: Sendable {
    let label: String
    let title: String
    let resetsAt: Date?

    func compactText(now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let resetsAt else {
            return "\(label) ↻ ?"
        }
        guard resetsAt > now else {
            return "\(label) ↻ pending"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEjm")
        }
        return "\(label) ↻ \(formatter.string(from: resetsAt))"
    }

    func menuText(formatter: DateFormatter, now: Date) -> String {
        guard let resetsAt else {
            return "\(title) limit reached · reset time unavailable"
        }
        guard resetsAt > now else {
            return "\(title) limit reached · waiting for updated reset time"
        }
        return "\(title) resets \(formatter.string(from: resetsAt))"
    }
}

struct UsageWindow: Sendable {
    let remainingPercent: Int
    let windowDurationMins: Double?
    let resetsAt: Date?

    init(_ window: RateLimitWindow) {
        let used = min(100, max(0, window.usedPercent ?? 0))
        remainingPercent = min(100, max(0, Int((100 - used).rounded())))
        windowDurationMins = window.windowDurationMins
        resetsAt = window.resetsAt.map { Date(timeIntervalSince1970: $0) }
    }

    func displayText(formatter: DateFormatter) -> String {
        guard let resetsAt else {
            return "\(remainingPercent)% remaining, reset unknown"
        }
        return "\(remainingPercent)% remaining, resets \(formatter.string(from: resetsAt))"
    }
}

private func approximately(_ value: Double?, _ target: Double) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - target) <= 1
}
