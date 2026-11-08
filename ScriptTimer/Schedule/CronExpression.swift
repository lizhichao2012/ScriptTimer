import Foundation

/// 标准 5 段 cron 表达式：分 时 日 月 周
/// 支持 `*`、列表 `,`、范围 `-`、步长 `/`、月份/星期英文缩写，以及 @daily 等宏。
/// 表达式会被展开成一组 CalendarSpec 规则，供调度器匹配。
struct CronExpression {
    /// 展开后的规则条数上限
    static let maxSpecs = 2000

    /// nil 表示通配（`*`）
    let minutes: [Int]?
    let hours: [Int]?
    let days: [Int]?
    let months: [Int]?
    /// 0 = 周日 … 6 = 周六
    let weekdays: [Int]?

    private static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *",
        "@annually": "0 0 1 1 *",
        "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *",
        "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]

    private static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static let weekdayNames: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
    ]

    init(_ text: String) throws {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let expanded = Self.macros[source] { source = expanded }
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5 else {
            throw ScheduleError("Cron 需要 5 个字段：分 时 日 月 周（当前 \(parts.count) 个）")
        }

        let minuteValues = try Self.parseField(parts[0], range: 0...59, name: "分钟")
        let hourValues = try Self.parseField(parts[1], range: 0...23, name: "小时")
        var dayValues = try Self.parseField(parts[2], range: 1...31, name: "日期")
        let monthValues = try Self.parseField(parts[3], range: 1...12, name: "月份", names: Self.monthNames)
        var weekdayValues = try Self.parseField(parts[4], range: 0...7, name: "星期", names: Self.weekdayNames)
            .map { Array(Set($0.map { $0 % 7 })).sorted() }

        // 取满整个范围的字段等同于通配，以减少展开数量。
        // 日/周需要特殊处理：cron 在两者都受限时是"任一满足"语义。
        let dayFull = dayValues?.count == 31
        let weekdayFull = weekdayValues?.count == 7
        if dayFull && weekdayValues == nil { dayValues = nil }
        if weekdayFull && dayValues == nil { weekdayValues = nil }
        if dayValues != nil && weekdayValues != nil && (dayFull || weekdayFull) {
            dayValues = nil
            weekdayValues = nil
        }

        minutes = minuteValues?.count == 60 ? nil : minuteValues
        hours = hourValues?.count == 24 ? nil : hourValues
        days = dayValues
        months = monthValues?.count == 12 ? nil : monthValues
        weekdays = weekdayValues
    }

    /// 展开后的规则条数
    var specCount: Int {
        let dayParts: Int
        switch (days, weekdays) {
        case (nil, nil): dayParts = 1
        case let (d?, nil): dayParts = d.count
        case let (nil, w?): dayParts = w.count
        case let (d?, w?): dayParts = d.count + w.count
        }
        return (minutes?.count ?? 1) * (hours?.count ?? 1) * (months?.count ?? 1) * dayParts
    }

    /// 展开为日历规则。
    /// 日、周都受限时生成两组独立规则，显式表达 cron 的 OR 语义。
    func specs() throws -> [CalendarSpec] {
        let count = specCount
        guard count <= Self.maxSpecs else {
            throw ScheduleError("该表达式会展开成 \(count) 条时间规则，超过上限 \(Self.maxSpecs)，请简化")
        }

        var dayParts: [(day: Int?, weekday: Int?)] = []
        switch (days, weekdays) {
        case (nil, nil): dayParts = [(nil, nil)]
        case let (d?, nil): dayParts = d.map { ($0, nil) }
        case let (nil, w?): dayParts = w.map { (nil, $0) }
        case let (d?, w?): dayParts = d.map { ($0, nil) } + w.map { (nil, $0) }
        }

        func optionals(_ values: [Int]?) -> [Int?] { values.map { $0.map(Optional.some) } ?? [nil] }

        var result: [CalendarSpec] = []
        result.reserveCapacity(count)
        for month in optionals(months) {
            for part in dayParts {
                for hour in optionals(hours) {
                    for minute in optionals(minutes) {
                        result.append(CalendarSpec(minute: minute, hour: hour, day: part.day,
                                                   month: month, weekday: part.weekday))
                    }
                }
            }
        }
        return result
    }

    private static func parseField(_ field: String, range: ClosedRange<Int>, name: String,
                                   names: [String: Int] = [:]) throws -> [Int]? {
        if field == "*" { return nil }

        func value(_ token: String) throws -> Int {
            if let v = Int(token) { return v }
            if let v = names[token] { return v }
            throw ScheduleError("\(name)字段无法识别：\(token)")
        }

        var result = Set<Int>()
        for rawItem in field.split(separator: ",", omittingEmptySubsequences: false) {
            let item = String(rawItem)
            guard !item.isEmpty else { throw ScheduleError("\(name)字段格式错误：\(field)") }

            var rangePart = item
            var step = 1
            var hasStep = false
            if let slash = item.firstIndex(of: "/") {
                rangePart = String(item[..<slash])
                let stepText = String(item[item.index(after: slash)...])
                guard let s = Int(stepText), s > 0 else {
                    throw ScheduleError("\(name)字段步长无效：\(item)")
                }
                step = s
                hasStep = true
            }

            let low: Int
            let high: Int
            if rangePart == "*" {
                low = range.lowerBound
                high = range.upperBound
            } else if let dash = rangePart.firstIndex(of: "-") {
                low = try value(String(rangePart[..<dash]))
                high = try value(String(rangePart[rangePart.index(after: dash)...]))
                guard low <= high else { throw ScheduleError("\(name)字段范围无效：\(rangePart)") }
            } else {
                low = try value(rangePart)
                // "5/15" 等价于 "5-最大值/15"
                high = hasStep ? range.upperBound : low
            }

            guard range.contains(low), range.contains(high) else {
                throw ScheduleError("\(name)超出范围 \(range.lowerBound)-\(range.upperBound)：\(item)")
            }
            for v in stride(from: low, through: high, by: step) { result.insert(v) }
        }
        return result.sorted()
    }
}
