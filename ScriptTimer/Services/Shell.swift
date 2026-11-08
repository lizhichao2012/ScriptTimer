import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    /// 同步执行命令并收集 stdout+stderr。不要在主线程调用耗时命令。
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum ShellEnv {
    static let fallbackPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// 从用户的交互式登录 shell 读取 PATH，与"终端"里看到的一致
    /// （从 Finder 启动的 App 只有系统默认 PATH；很多人把 Homebrew 配置写在 ~/.zshrc，非交互 shell 不会加载）
    static func loginPath() -> String {
        let marker = "__SCRIPTTIMER__"
        let command = "print -rn -- \"\(marker)${PATH}\(marker)\""
        var parts: [String] = []
        for flags in ["-ilc", "-lc"] {
            let result = Shell.run("/bin/zsh", [flags, command], timeout: 5)
            let segments = result.output.components(separatedBy: marker)
            if segments.count >= 3 {
                parts = segments[1].split(separator: ":").map(String.init).filter { !$0.isEmpty }
                if !parts.isEmpty { break }
            }
        }
        for p in fallbackPath.split(separator: ":").map(String.init) where !parts.contains(p) {
            parts.append(p)
        }
        // 去重并保持顺序
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    static func which(_ name: String, path: String) -> String? {
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
