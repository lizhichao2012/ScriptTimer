import Foundation

/// 计算"下次执行时间"：内置调度器和界面预览共用
enum NextRunCalculator {
    /// - Parameter lastRun: 间隔类任务的上一次（非手动）执行时间；未知时无法推算
    static func nextRuns(for schedule: Schedule, after date: Date, count: Int,
                         lastRun: Date? = nil, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        switch schedule {
        case .once(let target):
            return target > date ? [target] : []

        case .interval(let seconds):
            guard seconds > 0, let last = lastRun else { return [] }
            let step = TimeInterval(seconds)
            let elapsed = date.timeIntervalSince(last)
            let k = elapsed < 0 ? 1 : floor(elapsed / step) + 1
            let first = last.addingTimeInterval(k * step)
            return (0..<count).map { first.addingTimeInterval(Double($0) * step) }

        default:
            guard case .calendar(let specs)? = try? schedule.trigger(calendar: calendar) else { return [] }
            var result: [Date] = []
            var cursor = date
            while result.count < count, let next = next(after: cursor, specs: specs, calendar: calendar) {
                result.append(next)
                cursor = next
            }
            return result
        }
    }

    /// 严格晚于 date 的第一个匹配任一规则的整分钟
    static func next(after date: Date, specs: [CalendarSpec], calendar cal: Calendar) -> Date? {
        guard !specs.isEmpty else { return nil }
        let floorComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let floorMinute = cal.date(from: floorComps),
              let start = cal.date(byAdding: .minute, value: 1, to: floorMinute) else { return nil }
        let startDay = cal.startOfDay(for: start)

        // 最多向后看 8 年（覆盖 2 月 29 日这类规则）
        for offset in 0..<(366 * 8) {
            guard let day = cal.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let dc = cal.dateComponents([.month, .day, .weekday], from: day)
            guard let month = dc.month, let dom = dc.day, let weekday = dc.weekday else { continue }
            let wd = weekday - 1 // Calendar: 1 = 周日 → 0
            let daySpecs = specs.filter { $0.matchesDay(month: month, day: dom, weekday: wd) }
            if daySpecs.isEmpty { continue }

            for hour in 0..<24 {
                let hourSpecs = daySpecs.filter { Self.matches($0.hour, hour) }
                if hourSpecs.isEmpty { continue }
                for minute in 0..<60 where hourSpecs.contains(where: { Self.matches($0.minute, minute) }) {
                    guard let candidate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
                        continue
                    }
                    if candidate >= start { return candidate }
                }
            }
        }
        return nil
    }

    static func matches(_ field: Int?, _ value: Int) -> Bool {
        guard let field else { return true }
        return field == value
    }
}

extension CalendarSpec {
    func matchesDay(month: Int, day: Int, weekday: Int) -> Bool {
        NextRunCalculator.matches(self.month, month)
            && NextRunCalculator.matches(self.day, day)
            && NextRunCalculator.matches(self.weekday, weekday)
    }
}
