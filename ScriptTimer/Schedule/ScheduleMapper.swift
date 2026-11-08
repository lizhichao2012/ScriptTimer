import Foundation

struct ScheduleError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 一条日历匹配规则（分、时、日、月、周）；nil 字段表示通配
struct CalendarSpec: Hashable {
    var minute: Int? = nil
    var hour: Int? = nil
    var day: Int? = nil
    var month: Int? = nil
    /// 0 = 周日 … 6 = 周六
    var weekday: Int? = nil

}

enum LaunchTrigger: Equatable {
    /// 固定间隔（秒）
    case interval(seconds: Int)
    /// 匹配任一日历规则
    case calendar([CalendarSpec])
}

extension Schedule {
    /// 把调度规则展开为时间规则（同时用于校验）；规则无效时抛出 ScheduleError
    func trigger(calendar: Calendar = .current) throws -> LaunchTrigger {
        switch self {
        case .once(let date):
            let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            return .calendar([CalendarSpec(minute: c.minute, hour: c.hour, day: c.day, month: c.month)])

        case .interval(let seconds):
            guard seconds >= 60 else { throw ScheduleError("间隔至少为 1 分钟") }
            return .interval(seconds: seconds)

        case let .daily(hour, minute):
            try Self.checkTime(hour, minute)
            return .calendar([CalendarSpec(minute: minute, hour: hour)])

        case let .weekly(weekdays, hour, minute):
            try Self.checkTime(hour, minute)
            let days = Set(weekdays.map { $0 % 7 }).sorted()
            guard !days.isEmpty else { throw ScheduleError("请至少选择一天") }
            guard days.allSatisfy({ (0...6).contains($0) }) else { throw ScheduleError("星期无效") }
            return .calendar(days.map { CalendarSpec(minute: minute, hour: hour, weekday: $0) })

        case let .monthly(days, hour, minute):
            try Self.checkTime(hour, minute)
            let sorted = Set(days).sorted()
            guard !sorted.isEmpty else { throw ScheduleError("请至少选择一个日期") }
            guard sorted.allSatisfy({ (1...31).contains($0) }) else { throw ScheduleError("日期必须在 1-31 之间") }
            return .calendar(sorted.map { CalendarSpec(minute: minute, hour: hour, day: $0) })

        case .cron(let expression):
            return .calendar(try CronExpression(expression).specs())
        }
    }

    private static func checkTime(_ hour: Int, _ minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ScheduleError("时间无效：\(hour):\(minute)")
        }
    }

    var kind: ScheduleKind {
        switch self {
        case .once: return .once
        case .interval: return .interval
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .cron: return .cron
        }
    }

    var onceDate: Date? {
        if case .once(let date) = self { return date }
        return nil
    }

    /// 当前规则的时、分（用于切换重复方式时保留时间）
    var timeOfDay: (hour: Int, minute: Int) {
        switch self {
        case let .daily(h, m), let .weekly(_, h, m), let .monthly(_, h, m):
            return (h, m)
        case .once(let date):
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 9, c.minute ?? 0)
        default:
            return (9, 0)
        }
    }

    /// 切换到另一种重复方式时的默认值
    func converted(to kind: ScheduleKind, now: Date = Date()) -> Schedule {
        if kind == self.kind { return self }
        let (h, m) = timeOfDay
        switch kind {
        case .once:
            let cal = Calendar.current
            var date = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            if date <= now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
            return .once(date: date)
        case .interval: return .interval(seconds: 3600)
        case .daily: return .daily(hour: h, minute: m)
        case .weekly: return .weekly(weekdays: [1, 2, 3, 4, 5], hour: h, minute: m)
        case .monthly: return .monthly(days: [1], hour: h, minute: m)
        case .cron: return .cron(expression: String(format: "%d %d * * *", m, h))
        }
    }

    var summary: String {
        switch self {
        case .once(let date):
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return "仅一次 · \(f.string(from: date))"
        case .interval(let s):
            if s % 3600 == 0 { return "每 \(s / 3600) 小时" }
            return "每 \(max(1, s / 60)) 分钟"
        case let .daily(h, m):
            return "每天 \(Self.time(h, m))"
        case let .weekly(days, h, m):
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            let ordered = Set(days.map { $0 % 7 }).sorted { ($0 + 6) % 7 < ($1 + 6) % 7 }
            if ordered == [1, 2, 3, 4, 5] { return "工作日 \(Self.time(h, m))" }
            if ordered.count == 7 { return "每天 \(Self.time(h, m))" }
            return "每周" + ordered.map { names[$0] }.joined(separator: "、") + " \(Self.time(h, m))"
        case let .monthly(days, h, m):
            return "每月 " + Set(days).sorted().map(String.init).joined(separator: "、") + " 日 \(Self.time(h, m))"
        case .cron(let e):
            return "Cron · \(e)"
        }
    }

    static func time(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }
}
