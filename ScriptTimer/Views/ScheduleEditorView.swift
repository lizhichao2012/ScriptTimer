import SwiftUI

struct ScheduleEditorView: View {
    @Binding var schedule: Schedule

    var body: some View {
        Picker("重复方式", selection: Binding(
            get: { schedule.kind },
            set: { schedule = schedule.converted(to: $0) }
        )) {
            ForEach(ScheduleKind.allCases) { Text($0.title).tag($0) }
        }

        switch schedule {
        case .once(let date):
            DatePicker("执行时间", selection: Binding(
                get: { date },
                set: { schedule = .once(date: $0) }
            ), in: Date()..., displayedComponents: [.date, .hourAndMinute])

        case .interval(let seconds):
            intervalEditor(seconds)

        case let .daily(h, m):
            timePicker(h, m) { schedule = .daily(hour: $0, minute: $1) }

        case let .weekly(days, h, m):
            LabeledContent("星期") {
                WeekdayPicker(selection: Binding(
                    get: { Set(days) },
                    set: { schedule = .weekly(weekdays: $0.sorted(), hour: h, minute: m) }
                ))
            }
            timePicker(h, m) { schedule = .weekly(weekdays: days, hour: $0, minute: $1) }

        case let .monthly(days, h, m):
            LabeledContent("日期") {
                MonthDayPicker(selection: Binding(
                    get: { Set(days) },
                    set: { schedule = .monthly(days: $0.sorted(), hour: h, minute: m) }
                ))
            }
            timePicker(h, m) { schedule = .monthly(days: days, hour: $0, minute: $1) }
            if days.contains(where: { $0 > 28 }) {
                Text("没有该日期的月份（如 2 月 30 日）会跳过。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .cron(let expression):
            cronEditor(expression)
        }

        preview
    }

    // MARK: - 子编辑器

    private func timePicker(_ hour: Int, _ minute: Int, set: @escaping (Int, Int) -> Void) -> some View {
        DatePicker("时间", selection: Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                set(c.hour ?? 0, c.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
    }

    private func intervalEditor(_ seconds: Int) -> some View {
        let isHours = seconds >= 3600 && seconds % 3600 == 0
        let unit = isHours ? 3600 : 60
        let value = max(1, seconds / unit)
        return LabeledContent("间隔") {
            HStack(spacing: 6) {
                Text("每")
                TextField("数值", value: Binding(
                    get: { value },
                    set: { schedule = .interval(seconds: max(1, $0) * unit) }
                ), format: .number)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                Stepper("数值", value: Binding(
                    get: { value },
                    set: { schedule = .interval(seconds: max(1, $0) * unit) }
                ), in: 1...10_000)
                .labelsHidden()
                Picker("单位", selection: Binding(
                    get: { isHours },
                    set: { schedule = .interval(seconds: value * ($0 ? 3600 : 60)) }
                )) {
                    Text("分钟").tag(false)
                    Text("小时").tag(true)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func cronEditor(_ expression: String) -> some View {
        TextField("表达式", text: Binding(
            get: { expression },
            set: { schedule = .cron(expression: $0) }
        ), prompt: Text("分 时 日 月 周"))
        .font(.system(.body, design: .monospaced))

        let result = Result { try CronExpression(expression).specs() }
        switch result {
        case .success(let specs):
            Label(specs.count == 1 ? "有效" : "有效（\(specs.count) 条时间规则）", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text("格式：分(0-59) 时(0-23) 日(1-31) 月(1-12) 周(0-7，0 和 7 都是周日)")
            Text("支持 * , - / 以及 @daily @hourly @weekly @monthly")
            Text("例：0 9 * * 1-5 工作日 9:00 · */15 * * * * 每 15 分钟 · 30 8 1,15 * * 每月 1、15 日 8:30")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    // MARK: - 预览

    @ViewBuilder
    private var preview: some View {
        if case .interval = schedule {
            Text("从 App 启动或任务保存、启用时开始计时，不对齐整点；需要对齐整点请用 Cron（如 */15 * * * *）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let runs = NextRunCalculator.nextRuns(for: schedule, after: Date(), count: 5)
            LabeledContent("接下来的执行") {
                if runs.isEmpty {
                    Text("无").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(runs, id: \.self) { date in
                            Text(date.formatted(.dateTime.year().month().day().weekday().hour().minute()))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

/// 周一到周日的切换按钮
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let order = [1, 2, 3, 4, 5, 6, 0]
    private let names = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                Toggle(names[day], isOn: Binding(
                    get: { selection.contains(day) },
                    set: { on in
                        if on { selection.insert(day) } else { selection.remove(day) }
                    }
                ))
                .toggleStyle(.button)
            }
        }
    }
}

/// 1-31 号的网格选择
struct MonthDayPicker: View {
    @Binding var selection: Set<Int>
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .trailing, spacing: 4) {
            ForEach(1...31, id: \.self) { day in
                Toggle("\(day)", isOn: Binding(
                    get: { selection.contains(day) },
                    set: { on in
                        if on { selection.insert(day) } else { selection.remove(day) }
                    }
                ))
                .toggleStyle(.button)
                .frame(width: 34)
            }
        }
        .fixedSize()
    }
}
