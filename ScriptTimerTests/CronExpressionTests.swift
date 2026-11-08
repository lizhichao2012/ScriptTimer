import XCTest

final class CronExpressionTests: XCTestCase {
    func testEveryMinuteIsSingleWildcardSpec() throws {
        XCTAssertEqual(try CronExpression("* * * * *").specs(), [CalendarSpec()])
    }

    func testStepsAndRanges() throws {
        let cron = try CronExpression("*/15 9-10 * * *")
        XCTAssertEqual(cron.minutes, [0, 15, 30, 45])
        XCTAssertEqual(cron.hours, [9, 10])
        XCTAssertEqual(try cron.specs().count, 8)
    }

    func testStepWithStartValue() throws {
        XCTAssertEqual(try CronExpression("5/15 * * * *").minutes, [5, 20, 35, 50])
        XCTAssertEqual(try CronExpression("10-30/10 * * * *").minutes, [10, 20, 30])
    }

    func testListsAndWeekdays() throws {
        let cron = try CronExpression("0,30 8 * * 1,3,5")
        XCTAssertEqual(cron.weekdays, [1, 3, 5])
        XCTAssertNil(cron.days)
        let specs = try cron.specs()
        XCTAssertEqual(specs.count, 6)
        XCTAssertTrue(specs.allSatisfy { $0.hour == 8 && $0.day == nil })
    }

    func testSundayAsSeven() throws {
        XCTAssertEqual(try CronExpression("0 0 * * 7").weekdays, [0])
        XCTAssertEqual(try CronExpression("0 0 * * 0,7").weekdays, [0])
    }

    func testNames() throws {
        let cron = try CronExpression("0 9 * JAN,jul mon-fri")
        XCTAssertEqual(cron.months, [1, 7])
        XCTAssertEqual(cron.weekdays, [1, 2, 3, 4, 5])
    }

    func testDayOrWeekdaySemanticsProducesSeparateSpecs() throws {
        let specs = try CronExpression("0 9 15 * 1").specs()
        XCTAssertEqual(specs.count, 2)
        XCTAssertTrue(specs.contains(CalendarSpec(minute: 0, hour: 9, day: 15)))
        XCTAssertTrue(specs.contains(CalendarSpec(minute: 0, hour: 9, weekday: 1)))
        XCTAssertFalse(specs.contains { $0.day != nil && $0.weekday != nil })
    }

    func testFullRangesCollapseToWildcard() throws {
        let cron = try CronExpression("0-59 0-23 * 1-12 *")
        XCTAssertNil(cron.minutes)
        XCTAssertNil(cron.hours)
        XCTAssertNil(cron.months)
        // 日受限 + 周取满 → 每天
        let both = try CronExpression("0 9 15 * 0-6")
        XCTAssertNil(both.days)
        XCTAssertNil(both.weekdays)
    }

    func testMacros() throws {
        XCTAssertEqual(try CronExpression("@daily").specs(), [CalendarSpec(minute: 0, hour: 0)])
        XCTAssertEqual(try CronExpression("@hourly").specs(), [CalendarSpec(minute: 0)])
    }

    func testWorkHoursEveryFiveMinutesFitsUnderCap() throws {
        XCTAssertEqual(try CronExpression("*/5 9-17 * * 1-5").specs().count, 12 * 9 * 5)
    }

    func testExpansionCap() {
        XCTAssertThrowsError(try CronExpression("0-58 0-22 1-2 * *").specs())
    }

    func testInvalidExpressions() {
        for bad in ["60 * * * *", "* * *", "*/0 * * * *", "a * * * *", "5-1 * * * *",
                    "* 24 * * *", "* * 0 * *", "* * * 13 *", "* * * * 8", "1,,2 * * * *"] {
            XCTAssertThrowsError(try CronExpression(bad), bad)
        }
    }
}
