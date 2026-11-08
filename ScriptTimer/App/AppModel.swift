import AppKit
import Foundation
import Observation
import ServiceManagement

/// App 的全部状态 + 内置调度器。
/// 任务只在 ScriptTimer 运行期间按时执行：每秒检查一次到点的任务并启动它。
@MainActor
@Observable
final class AppModel {
    var tasks: [ScriptTask] = []
    var history: [UUID: [RunRecord]] = [:]
    /// 每个启用任务的下一次执行时间（调度器的唯一依据，也供界面显示）
    var nextRuns: [UUID: Date] = [:]
    /// 正在执行中的任务
    var running: Set<UUID> = []
    var selection: UUID?
    var errorMessage: String?
    var deleteCandidate: UUID?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// 用户登录 shell 的 PATH（后台加载完成前为兜底值）
    var pathEnv = ShellEnv.fallbackPath

    @ObservationIgnored let store = TaskStore()
    @ObservationIgnored private let runner: ScriptRunner
    /// 进程启动在这个串行队列上执行，不阻塞界面
    @ObservationIgnored private let queue = DispatchQueue(label: "com.scripttimer.runner")
    @ObservationIgnored private var historyStamps: [UUID: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        runner = ScriptRunner(store: store)
        start()
    }

    // MARK: - 启动

    private func start() {
        do {
            try store.ensureDirectories()
            tasks = try store.loadTasks()
        } catch {
            errorMessage = "初始化失败：\(error.localizedDescription)"
        }
        disableMissedOnceTasks()
        selection = tasks.first?.id
        refreshHistory(force: true)
        rescheduleAll()

        // 防止 App Nap：窗口关闭、只剩菜单栏时计时器也要准时（不阻止电脑正常睡眠）
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "按时执行定时脚本"
        )

        let runner = runner
        queue.async { [weak self] in
            runner.removeLegacyLaunchAgents()
            let path = runner.pathEnv
            DispatchQueue.main.async { self?.pathEnv = path }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        // .common：菜单展开、窗口拖动时也照常触发
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 系统时间或时区改变后重新计算；从睡眠唤醒后立即检查
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescheduleAll() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
    }

    private func tick() {
        runDueTasks()
        tickCount += 1
        if tickCount % 3 == 0 { refreshHistory(force: false) }
    }

    /// App 没开着的时候错过的一次性任务不再补跑，直接停用
    private func disableMissedOnceTasks() {
        let now = Date()
        var changed = false
        for i in tasks.indices where tasks[i].isActive {
            if let date = tasks[i].schedule.onceDate, date <= now {
                tasks[i].enabled = false
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - 调度

    private func runDueTasks() {
        let now = Date()
        let due = nextRuns.filter { $0.value <= now }
        guard !due.isEmpty else { return }

        var changed = false
        for (id, dueDate) in due {
            guard let i = index(id), tasks[i].isActive else {
                nextRuns[id] = nil
                continue
            }
            let task = tasks[i]
            // 上一次还没跑完就跳过本次，避免同一脚本并发执行
            if !running.contains(id) {
                launch(task, manual: false)
            }
            if task.schedule.onceDate != nil {
                tasks[i].completed = true
                tasks[i].enabled = false
                nextRuns[id] = nil
                changed = true
            } else {
                nextRuns[id] = nextDate(for: task, after: now, previousDue: dueDate)
            }
        }
        if changed { persist() }
    }

    /// 计算 after 之后的下一次执行时间
    /// 错过的多次执行（如电脑睡眠期间）只补跑一次，然后从当前时间往后排
    private func nextDate(for task: ScriptTask, after: Date, previousDue: Date?) -> Date? {
        switch task.schedule {
        case .interval(let seconds):
            let step = TimeInterval(max(60, seconds))
            if let previousDue {
                let next = previousDue.addingTimeInterval(step)
                return next > after ? next : after.addingTimeInterval(step)
            }
            return after.addingTimeInterval(step)
        case .once(let date):
            return date > after ? date : nil
        default:
            return NextRunCalculator.nextRuns(for: task.schedule, after: after, count: 1).first
        }
    }

    private func reschedule(_ task: ScriptTask) {
        nextRuns[task.id] = task.isActive ? nextDate(for: task, after: Date(), previousDue: nil) : nil
    }

    private func rescheduleAll() {
        var result: [UUID: Date] = [:]
        let now = Date()
        for task in tasks where task.isActive {
            // 间隔任务保留原有节奏，其它按当前时间重新计算
            if case .interval = task.schedule, let existing = nextRuns[task.id], existing > now {
                result[task.id] = existing
            } else {
                result[task.id] = nextDate(for: task, after: now, previousDue: nil)
            }
        }
        nextRuns = result
    }

    private func launch(_ task: ScriptTask, manual: Bool) {
        running.insert(task.id)
        let runner = runner, id = task.id, name = task.name
        queue.async { [weak self] in
            do {
                try runner.run(task, manual: manual) {
                    DispatchQueue.main.async {
                        self?.running.remove(id)
                        self?.refreshHistory(force: false)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.running.remove(id)
                    self?.errorMessage = "「\(name)」启动失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 查询

    func task(_ id: UUID) -> ScriptTask? { tasks.first { $0.id == id } }
    private func index(_ id: UUID) -> Int? { tasks.firstIndex { $0.id == id } }

    func lastRecord(_ task: ScriptTask) -> RunRecord? { history[task.id]?.first }

    func statusText(_ task: ScriptTask) -> String {
        if running.contains(task.id) { return "运行中…" }
        if task.completed { return "已完成" }
        if task.scriptPath.isEmpty { return "未选择脚本文件" }
        if task.isActive, task.scriptProblem != nil { return "⚠️ 脚本文件不存在" }
        if !task.enabled {
            if let date = task.schedule.onceDate, date <= Date() { return "已停用（时间已过）" }
            return "已停用"
        }
        if let next = nextRuns[task.id] { return "下次：\(next.runText)" }
        return "无后续执行时间"
    }

    func upcoming(limit: Int) -> [(task: ScriptTask, date: Date)] {
        tasks.compactMap { t in nextRuns[t.id].map { (task: t, date: $0) } }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { $0 }
    }

    func recentRuns(limit: Int) -> [(task: ScriptTask, record: RunRecord)] {
        tasks.flatMap { t in (history[t.id] ?? []).prefix(limit).map { (task: t, record: $0) } }
            .sorted { $0.record.start > $1.record.start }
            .prefix(limit)
            .map { $0 }
    }

    var hasRecentFailure: Bool {
        tasks.contains { lastRecord($0).map { !$0.succeeded } ?? false }
    }

    func interpreterHint(for type: ScriptType) -> String {
        let fallback = type.defaultInterpreter
        if fallback.hasPrefix("/") { return fallback }
        return ShellEnv.which(fallback, path: pathEnv) ?? "\(fallback)（在 PATH 中查找）"
    }

    // MARK: - 修改

    func addTask() {
        var task = ScriptTask()
        task.name = "新任务 \(tasks.count + 1)"
        task.enabled = false
        tasks.append(task)
        persist()
        selection = task.id
    }

    /// 保存编辑后的任务；成功返回 true
    @discardableResult
    func save(_ draft: ScriptTask, enable: Bool = false) -> Bool {
        var task = draft
        task.name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.name.isEmpty { task.name = "未命名任务" }

        if let old = index(task.id).map({ tasks[$0] }) {
            task.enabled = old.enabled
            task.completed = old.completed
            // 一次性任务完成后改了时间 → 重新启用
            if old.completed && task.schedule != old.schedule {
                task.completed = false
                task.enabled = true
            }
        }
        if enable {
            task.enabled = true
            task.completed = false
        }

        do {
            _ = try task.schedule.trigger()
            if task.isActive, let problem = task.scriptProblem {
                throw ScheduleError(problem)
            }
            if task.isActive, let date = task.schedule.onceDate, date <= Date() {
                throw ScheduleError("执行时间已经过去，请选择将来的时间")
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        let scheduleChanged = self.task(task.id)?.schedule != task.schedule
            || self.task(task.id)?.isActive != task.isActive
        if let i = index(task.id) { tasks[i] = task } else { tasks.append(task) }
        persist()
        // 只改脚本内容时不打乱原有节奏
        if scheduleChanged || nextRuns[task.id] == nil { reschedule(task) }
        return true
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let i = index(id) else { return }
        var task = tasks[i]
        if enabled {
            do {
                if let problem = task.scriptProblem { throw ScheduleError(problem) }
                _ = try task.schedule.trigger()
                if let date = task.schedule.onceDate, date <= Date() {
                    throw ScheduleError("一次性任务的执行时间已经过去，请先修改时间")
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            task.completed = false
        }
        task.enabled = enabled
        tasks[i] = task
        persist()
        reschedule(task)
    }

    func delete(_ id: UUID) {
        guard let i = index(id) else { return }
        let task = tasks.remove(at: i)
        if selection == id { selection = tasks.first?.id }
        history[id] = nil
        nextRuns[id] = nil
        historyStamps[id] = nil
        persist()
        let store = store
        queue.async { store.deleteFiles(for: task) }
    }

    func runNow(_ id: UUID) {
        guard let task = task(id) else { return }
        if let problem = task.scriptProblem {
            errorMessage = problem
            return
        }
        if running.contains(id) {
            errorMessage = "「\(task.name)」正在运行中，请等它结束后再试。"
            return
        }
        launch(task, manual: true)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "设置开机启动失败：\(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if on && status == .requiresApproval {
            errorMessage = "请在“系统设置 → 通用 → 登录项”中允许 ScriptTimer。"
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func revealLogs(_ task: ScriptTask) {
        let dir = store.logDir(for: task)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    // MARK: - 内部

    private func persist() {
        do { try store.saveTasks(tasks) } catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }

    private func refreshHistory(force: Bool) {
        for task in tasks {
            let stamp = store.historyModificationDate(for: task)
            if !force, stamp == historyStamps[task.id] { continue }
            historyStamps[task.id] = stamp
            history[task.id] = store.history(for: task)
        }
    }
}

extension Date {
    /// "今天 09:00" / "明天 09:00" / "11月9日 09:00"
    var runText: String {
        let cal = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(self) { return "今天 \(time)" }
        if cal.isDateInTomorrow(self) { return "明天 \(time)" }
        if cal.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month().day().hour().minute())
        }
        return formatted(date: .abbreviated, time: .shortened)
    }
}
