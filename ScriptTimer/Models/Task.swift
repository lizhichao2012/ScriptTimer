import Foundation

enum ScriptType: String, Codable, CaseIterable, Identifiable {
    case zsh, bash, python

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zsh: return "Zsh"
        case .bash: return "Bash"
        case .python: return "Python 3"
        }
    }

    /// 默认解释器；不以 / 开头的会在用户 PATH 中查找
    var defaultInterpreter: String {
        switch self {
        case .zsh: return "/bin/zsh"
        case .bash: return "/bin/bash"
        case .python: return "python3"
        }
    }

    /// 根据首行 #! 和扩展名推断脚本类型
    static func detect(path: String, firstLine: String?) -> ScriptType {
        if let line = firstLine, line.hasPrefix("#!") {
            if line.contains("python") { return .python }
            if line.contains("bash") { return .bash }
            if line.contains("zsh") || line.hasSuffix("/sh") || line.contains("/sh ") { return .zsh }
        }
        switch (path as NSString).pathExtension.lowercased() {
        case "py": return .python
        case "bash": return .bash
        default: return .zsh
        }
    }

    static func detect(fileAt path: String) -> ScriptType {
        let firstLine = (try? String(contentsOfFile: path, encoding: .utf8))?
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        return detect(path: path, firstLine: firstLine)
    }
}

struct EnvVar: Codable, Hashable, Identifiable {
    var id = UUID()
    var key = ""
    var value = ""
}

enum Schedule: Codable, Hashable {
    case once(date: Date)
    case interval(seconds: Int)
    case daily(hour: Int, minute: Int)
    /// weekdays: 0 = 周日 … 6 = 周六（与 cron 一致）
    case weekly(weekdays: [Int], hour: Int, minute: Int)
    case monthly(days: [Int], hour: Int, minute: Int)
    case cron(expression: String)
}

enum ScheduleKind: String, CaseIterable, Identifiable {
    case once, interval, daily, weekly, monthly, cron

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: return "仅一次"
        case .interval: return "每隔一段时间"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .cron: return "Cron 表达式"
        }
    }
}

struct ScriptTask: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "新任务"
    var enabled = true
    /// 一次性任务执行完成后置为 true
    var completed = false
    /// 要执行的脚本文件路径（支持 ~）
    var scriptPath = ""
    var type: ScriptType = .zsh
    /// 为空时使用 type.defaultInterpreter
    var interpreterPath = ""
    var useLoginShell = false
    /// 为空时为脚本所在目录
    var workingDirectory = ""
    var environment: [EnvVar] = []
    var schedule: Schedule = .daily(hour: 9, minute: 0)
    var notifyOnFailure = true
    var createdAt = Date()

    var idString: String { id.uuidString.lowercased() }
    var isActive: Bool { enabled && !completed }

    /// 展开 ~ 后的脚本绝对路径
    var resolvedScriptPath: String {
        (scriptPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    /// 检查脚本文件；有问题时返回错误说明
    var scriptProblem: String? {
        let path = resolvedScriptPath
        if path.isEmpty { return "请先选择脚本文件" }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) { return "脚本文件不存在：\(path)" }
        if isDir.boolValue { return "这是一个文件夹，请选择脚本文件：\(path)" }
        if !FileManager.default.isReadableFile(atPath: path) { return "没有读取权限：\(path)" }
        return nil
    }
}

extension ScriptTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScriptTask()
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? defaults.completed
        scriptPath = try c.decodeIfPresent(String.self, forKey: .scriptPath) ?? ""
        type = try c.decodeIfPresent(ScriptType.self, forKey: .type) ?? defaults.type
        interpreterPath = try c.decodeIfPresent(String.self, forKey: .interpreterPath) ?? ""
        useLoginShell = try c.decodeIfPresent(Bool.self, forKey: .useLoginShell) ?? false
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        environment = try c.decodeIfPresent([EnvVar].self, forKey: .environment) ?? []
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? defaults.schedule
        notifyOnFailure = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFailure) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
