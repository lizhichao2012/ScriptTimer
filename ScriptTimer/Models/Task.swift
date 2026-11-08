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

    var fileExtension: String { self == .python ? "py" : "sh" }

    /// 默认解释器；不以 / 开头的会在用户 PATH 中查找
    var defaultInterpreter: String {
        switch self {
        case .zsh: return "/bin/zsh"
        case .bash: return "/bin/bash"
        case .python: return "python3"
        }
    }

    var template: String {
        switch self {
        case .zsh, .bash:
            return "# 在这里编写脚本，例如：\necho \"Hello from ScriptTimer: $(date)\"\n"
        case .python:
            return "# 在这里编写脚本，例如：\nfrom datetime import datetime\nprint(f\"Hello from ScriptTimer: {datetime.now()}\")\n"
        }
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
    var type: ScriptType = .zsh
    /// 为空时使用 type.defaultInterpreter
    var interpreterPath = ""
    var useLoginShell = false
    /// 为空时为用户主目录
    var workingDirectory = ""
    var environment: [EnvVar] = []
    var schedule: Schedule = .daily(hour: 9, minute: 0)
    var notifyOnFailure = true
    var createdAt = Date()
    /// 脚本正文：单独存储在 scripts/<id>.<ext>，不写入 tasks.json
    var script = ""

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, completed, type, interpreterPath, useLoginShell
        case workingDirectory, environment, schedule, notifyOnFailure, createdAt
    }

    var idString: String { id.uuidString.lowercased() }
    var label: String { "com.scripttimer.task.\(idString)" }
    var isActive: Bool { enabled && !completed }
}

extension ScriptTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScriptTask()
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? defaults.completed
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
