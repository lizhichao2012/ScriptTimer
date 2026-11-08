import Foundation

/// 负责 ~/Library/Application Support/ScriptTimer 下的文件：
/// tasks.json（任务配置）、logs/（输出与历史）。脚本文件由用户自己管理，App 只记录路径。
final class TaskStore: @unchecked Sendable {
    let root: URL
    /// 仅用于清理旧版本留下的 LaunchAgent
    let launchAgentsDir: URL
    private let fm = FileManager.default

    init(root: URL? = nil, launchAgentsDir: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.root = root ?? home.appendingPathComponent("Library/Application Support/ScriptTimer", isDirectory: true)
        self.launchAgentsDir = launchAgentsDir ?? home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    var tasksFile: URL { root.appendingPathComponent("tasks.json") }
    var logsDir: URL { root.appendingPathComponent("logs", isDirectory: true) }
    /// 旧版本在 App 内编辑的脚本存放位置，仅用于迁移
    private var legacyScriptsDir: URL { root.appendingPathComponent("scripts", isDirectory: true) }

    func logDir(for task: ScriptTask) -> URL { logsDir.appendingPathComponent(task.idString, isDirectory: true) }
    func historyFile(for task: ScriptTask) -> URL { logDir(for: task).appendingPathComponent("history.jsonl") }
    func logURL(for task: ScriptTask, record: RunRecord) -> URL { logDir(for: task).appendingPathComponent(record.log) }

    func ensureDirectories() throws {
        for dir in [root, logsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Tasks

    func loadTasks() throws -> [ScriptTask] {
        guard fm.fileExists(atPath: tasksFile.path) else { return [] }
        let data = try Data(contentsOf: tasksFile)
        var tasks = try JSONDecoder().decode([ScriptTask].self, from: data)
        // 迁移：旧版本的脚本正文保存在 scripts/<id>.sh|.py，直接把它当作脚本路径
        for i in tasks.indices where tasks[i].scriptPath.isEmpty {
            for ext in ["sh", "py"] {
                let legacy = legacyScriptsDir.appendingPathComponent("\(tasks[i].idString).\(ext)")
                if fm.fileExists(atPath: legacy.path) {
                    tasks[i].scriptPath = legacy.path
                    break
                }
            }
        }
        return tasks
    }

    func saveTasks(_ tasks: [ScriptTask]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        try encoder.encode(tasks).write(to: tasksFile, options: .atomic)
    }

    /// 删除任务的运行日志（不会动用户的脚本文件）
    func deleteFiles(for task: ScriptTask) {
        try? fm.removeItem(at: logDir(for: task))
    }
}
