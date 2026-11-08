import Foundation

/// 负责 ~/Library/Application Support/ScriptTimer 下的所有文件：
/// tasks.json（任务配置）、scripts/（脚本正文）、logs/（输出与历史）
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
    var scriptsDir: URL { root.appendingPathComponent("scripts", isDirectory: true) }
    var logsDir: URL { root.appendingPathComponent("logs", isDirectory: true) }

    func logDir(for task: ScriptTask) -> URL { logsDir.appendingPathComponent(task.idString, isDirectory: true) }
    func historyFile(for task: ScriptTask) -> URL { logDir(for: task).appendingPathComponent("history.jsonl") }
    func logURL(for task: ScriptTask, record: RunRecord) -> URL { logDir(for: task).appendingPathComponent(record.log) }
    func scriptURL(for task: ScriptTask) -> URL {
        scriptsDir.appendingPathComponent("\(task.idString).\(task.type.fileExtension)")
    }

    func ensureDirectories() throws {
        for dir in [root, scriptsDir, logsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Tasks

    func loadTasks() throws -> [ScriptTask] {
        guard fm.fileExists(atPath: tasksFile.path) else { return [] }
        let data = try Data(contentsOf: tasksFile)
        var tasks = try JSONDecoder().decode([ScriptTask].self, from: data)
        for i in tasks.indices {
            tasks[i].script = (try? String(contentsOf: scriptURL(for: tasks[i]), encoding: .utf8)) ?? ""
        }
        return tasks
    }

    func saveTasks(_ tasks: [ScriptTask]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        try encoder.encode(tasks).write(to: tasksFile, options: .atomic)
    }

    func writeScript(_ task: ScriptTask) throws {
        let url = scriptURL(for: task)
        try task.script.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        // 脚本类型变化后清理旧扩展名的文件
        for type in ScriptType.allCases where type.fileExtension != task.type.fileExtension {
            try? fm.removeItem(at: scriptsDir.appendingPathComponent("\(task.idString).\(type.fileExtension)"))
        }
    }

    func deleteFiles(for task: ScriptTask) {
        for type in ScriptType.allCases {
            try? fm.removeItem(at: scriptsDir.appendingPathComponent("\(task.idString).\(type.fileExtension)"))
        }
        try? fm.removeItem(at: logDir(for: task))
    }
}
