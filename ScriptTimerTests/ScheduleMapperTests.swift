import XCTest

final class ScheduleMapperTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func testDaily() throws {
        XCTAssertEqual(try Schedule.daily(hour: 9, minute: 30).trigger(calendar: cal),
                       .calendar([CalendarSpec(minute: 30, hour: 9)]))
    }

    func testWeeklyNormalizesSevenToSunday() throws {
        let trigger = try Schedule.weekly(weekdays: [7, 1, 1], hour: 8, minute: 0).trigger(calendar: cal)
        XCTAssertEqual(trigger, .calendar([CalendarSpec(minute: 0, hour: 8, weekday: 0),
                                           CalendarSpec(minute: 0, hour: 8, weekday: 1)]))
    }

    func testMonthly() throws {
        let trigger = try Schedule.monthly(days: [15, 1], hour: 0, minute: 5).trigger(calendar: cal)
        XCTAssertEqual(trigger, .calendar([CalendarSpec(minute: 5, hour: 0, day: 1),
                                           CalendarSpec(minute: 5, hour: 0, day: 15)]))
    }

    func testOnceUsesMonthDayHourMinute() throws {
        let date = cal.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 18, minute: 45))!
        XCTAssertEqual(try Schedule.once(date: date).trigger(calendar: cal),
                       .calendar([CalendarSpec(minute: 45, hour: 18, day: 24, month: 12)]))
        XCTAssertEqual(Schedule.once(date: date).onceDate, date)
    }

    func testInterval() throws {
        XCTAssertEqual(try Schedule.interval(seconds: 300).trigger(), .interval(seconds: 300))
        XCTAssertThrowsError(try Schedule.interval(seconds: 30).trigger())
    }

    func testInvalidSchedules() {
        XCTAssertThrowsError(try Schedule.weekly(weekdays: [], hour: 9, minute: 0).trigger())
        XCTAssertThrowsError(try Schedule.monthly(days: [], hour: 9, minute: 0).trigger())
        XCTAssertThrowsError(try Schedule.monthly(days: [32], hour: 9, minute: 0).trigger())
        XCTAssertThrowsError(try Schedule.daily(hour: 24, minute: 0).trigger())
        XCTAssertThrowsError(try Schedule.cron(expression: "bad").trigger())
    }

    func testScheduleCodableRoundTrip() throws {
        let schedules: [Schedule] = [.interval(seconds: 600), .weekly(weekdays: [1, 3], hour: 7, minute: 5),
                                     .cron(expression: "*/5 * * * *"), .once(date: Date(timeIntervalSince1970: 1_800_000_000))]
        for s in schedules {
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(Schedule.self, from: data), s)
        }
    }

    func testSummary() {
        XCTAssertEqual(Schedule.daily(hour: 9, minute: 5).summary, "每天 09:05")
        XCTAssertEqual(Schedule.weekly(weekdays: [1, 2, 3, 4, 5], hour: 9, minute: 0).summary, "工作日 09:00")
        XCTAssertEqual(Schedule.weekly(weekdays: [0, 1], hour: 9, minute: 0).summary, "每周一、日 09:00")
        XCTAssertEqual(Schedule.interval(seconds: 7200).summary, "每 2 小时")
        XCTAssertEqual(Schedule.interval(seconds: 900).summary, "每 15 分钟")
    }
}
