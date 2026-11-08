import XCTest

final class NextRunCalculatorTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 2026-11-07 是周六
    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func runs(_ schedule: Schedule, after: Date, count: Int = 3, lastRun: Date? = nil) -> [Date] {
        NextRunCalculator.nextRuns(for: schedule, after: after, count: count, lastRun: lastRun, calendar: cal)
    }

    func testDaily() {
        XCTAssertEqual(runs(.daily(hour: 9, minute: 0), after: date(2026, 11, 7, 8, 30), count: 2),
                       [date(2026, 11, 7, 9, 0), date(2026, 11, 8, 9, 0)])
        // 恰好在执行时刻 → 下一次是明天
        XCTAssertEqual(runs(.daily(hour: 9, minute: 0), after: date(2026, 11, 7, 9, 0), count: 1),
                       [date(2026, 11, 8, 9, 0)])
    }

    func testWeekly() {
        XCTAssertEqual(runs(.weekly(weekdays: [1], hour: 9, minute: 0), after: date(2026, 11, 7, 12, 0), count: 2),
                       [date(2026, 11, 9, 9, 0), date(2026, 11, 16, 9, 0)])
    }

    func testCronDayOrWeekday() {
        // 每月 15 日 或 每周一
        XCTAssertEqual(runs(.cron(expression: "0 9 15 * 1"), after: date(2026, 11, 7, 12, 0), count: 3),
                       [date(2026, 11, 9, 9, 0), date(2026, 11, 15, 9, 0), date(2026, 11, 16, 9, 0)])
    }

    func testCronSteps() {
        XCTAssertEqual(runs(.cron(expression: "*/15 * * * *"), after: date(2026, 11, 7, 10, 7, 30), count: 2),
                       [date(2026, 11, 7, 10, 15), date(2026, 11, 7, 10, 30)])
    }

    func testCronHourWildcardMinute() {
        // "* 9 * * *"：9 点内每分钟
        XCTAssertEqual(runs(.cron(expression: "* 9 * * *"), after: date(2026, 11, 7, 9, 30), count: 1),
                       [date(2026, 11, 7, 9, 31)])
    }

    func testMonthlySkipsShortMonths() {
        XCTAssertEqual(runs(.monthly(days: [31], hour: 0, minute: 0), after: date(2026, 11, 7, 0, 0), count: 2),
                       [date(2026, 12, 31, 0, 0), date(2027, 1, 31, 0, 0)])
    }

    func testOnce() {
        let target = date(2026, 11, 8, 10, 0)
        XCTAssertEqual(runs(.once(date: target), after: date(2026, 11, 7, 10, 0)), [target])
        XCTAssertEqual(runs(.once(date: target), after: date(2026, 11, 9, 10, 0)), [])
    }

    func testInterval() {
        let last = date(2026, 11, 7, 10, 0)
        XCTAssertEqual(runs(.interval(seconds: 600), after: date(2026, 11, 7, 10, 25), count: 2, lastRun: last),
                       [date(2026, 11, 7, 10, 30), date(2026, 11, 7, 10, 40)])
        XCTAssertEqual(runs(.interval(seconds: 600), after: date(2026, 11, 7, 10, 25)), [])
    }

    func testFeb29() {
        XCTAssertEqual(runs(.cron(expression: "0 0 29 2 *"), after: date(2026, 11, 7, 0, 0), count: 1),
                       [date(2028, 2, 29, 0, 0)])
    }
}
