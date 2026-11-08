import Foundation

/// runner.sh 每次执行后向 logs/<id>/history.jsonl 追加的一行
struct RunRecord: Codable, Hashable, Identifiable {
    var start: Double
    var end: Double
    var exitCode: Int
    /// 日志文件名（位于 logs/<id>/ 下）
    var log: String
    var manual: Bool?

    var id: String { log }
    var startDate: Date { Date(timeIntervalSince1970: start) }
    var duration: TimeInterval { max(0, end - start) }
    var succeeded: Bool { exitCode == 0 }
    var isManual: Bool { manual ?? false }
}
