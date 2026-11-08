import Foundation

/// 启动 runner.sh 执行任务脚本。所有方法只在 AppModel 的串行后台队列上调用。
final class ScriptRunner: @unchecked Sendable {
    let store: TaskStore
    /// 用户交互式登录 shell 的 PATH，首次使用时获取（可能耗时数秒，不要在主线程首次访问）
    private(set) lazy var pathEnv: String = ShellEnv.loginPath()

    private let lock = NSLock()
    private var processes: [Process] = []

    init(store: TaskStore) {
        self.store = store
    }

    func interpreter(for task: ScriptTask) -> String {
        let custom = (task.interpreterPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if !custom.isEmpty { return custom }
        let fallback = task.type.defaultInterpreter
        if fallback.hasPrefix("/") { return fallback }
        return ShellEnv.which(fallback, path: pathEnv) ?? fallback
    }

    private func environment(for task: ScriptTask) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = pathEnv
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUNBUFFERED"] = "1"
        for v in task.environment {
            let key = v.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { env[key] = v.value }
        }
        return env
    }

    private func workingDirectory(for task: ScriptTask) -> URL {
        let dir = (task.workingDirectory.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        return URL(fileURLWithPath: dir.isEmpty ? NSHomeDirectory() : dir, isDirectory: true)
    }

    /// 启动一次执行；脚本结束后在任意线程回调 onExit
    func run(_ task: ScriptTask, manual: Bool, onExit: @escaping @Sendable () -> Void) throws {
        guard let runnerPath = Bundle.main.path(forResource: "runner", ofType: "sh") else {
            throw ScheduleError("App 包内缺少 runner.sh")
        }
        let workDir = workingDirectory(for: task)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw ScheduleError("工作目录不存在：\(workDir.path)")
        }
        try FileManager.default.createDirectory(at: store.logDir(for: task), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            runnerPath,
            task.idString,
            task.name,
            store.scriptURL(for: task).path,
            task.useLoginShell ? "1" : "0",
            task.notifyOnFailure ? "1" : "0",
            manual ? "1" : "0",
            interpreter(for: task),
        ]
        process.environment = environment(for: task)
        process.currentDirectoryURL = workDir
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            self?.forget(finished)
            onExit()
        }
        lock.lock()
        processes.append(process)
        lock.unlock()
        do {
            try process.run()
        } catch {
            forget(process)
            throw error
        }
    }

    private func forget(_ process: Process) {
        lock.lock()
        processes.removeAll { $0 === process }
        lock.unlock()
    }

    /// 清理旧版本（基于 launchd 的后台执行）留下的 LaunchAgent 和文件
    func removeLegacyLaunchAgents() {
        let fm = FileManager.default
        let dir = store.launchAgentsDir
        let prefix = "com.scripttimer.task."
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where file.hasPrefix(prefix) && file.hasSuffix(".plist") {
            let label = String(file.dropLast(".plist".count))
            Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            try? fm.removeItem(at: dir.appendingPathComponent(file))
        }
        try? fm.removeItem(at: store.root.appendingPathComponent("runner.sh"))
        try? fm.removeItem(at: store.root.appendingPathComponent("state"))
    }
}
