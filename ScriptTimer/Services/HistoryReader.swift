import Foundation

extension TaskStore {
    func historyModificationDate(for task: ScriptTask) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: historyFile(for: task).path))?[.modificationDate] as? Date
    }

    /// 读取执行历史，最新的在前
    func history(for task: ScriptTask) -> [RunRecord] {
        guard let text = try? String(contentsOf: historyFile(for: task), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        let records = text.split(separator: "\n").compactMap { line in
            try? decoder.decode(RunRecord.self, from: Data(line.utf8))
        }
        return records.reversed()
    }

    /// 读取日志内容，过大时只保留末尾
    func readLog(at url: URL, maxBytes: Int = 512 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return offset > 0 ? "…（仅显示最后 \(maxBytes / 1024) KB）\n" + text : text
    }
}
