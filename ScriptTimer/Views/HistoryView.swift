import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    let task: ScriptTask
    @State private var selectedID: String?

    private var records: [RunRecord] { model.history[task.id] ?? [] }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(records, selection: $selectedID) { record in
                    HStack(spacing: 8) {
                        StatusDot(record: record)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.startDate.formatted(date: .numeric, time: .standard))
                                .monospacedDigit()
                            Text(detail(record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(record.id)
                }
                .overlay {
                    if records.isEmpty {
                        Text("还没有执行记录").foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    Text("保留最近 50 份日志").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("在 Finder 中显示") { model.revealLogs(task) }
                        .controlSize(.small)
                }
                .padding(8)
            }
            .frame(width: 270)

            Divider()

            if let record = records.first(where: { $0.id == selectedID }) {
                LogView(url: model.store.logURL(for: task, record: record), store: model.store)
            } else {
                Text("选择一条记录查看输出")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selectedID == nil { selectedID = records.first?.id } }
        .onChange(of: records.first?.id) { _, newest in
            // 有新的执行记录时自动选中
            selectedID = newest
        }
    }

    private func detail(_ record: RunRecord) -> String {
        var parts = [record.succeeded ? "成功" : "失败 · 退出码 \(record.exitCode)"]
        parts.append("耗时 \(Int(record.duration)) 秒")
        if record.isManual { parts.append("手动") }
        return parts.joined(separator: " · ")
    }
}

struct LogView: View {
    let url: URL
    let store: TaskStore
    @State private var text = ""

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? "（无输出）" : text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: url) {
            let store = store, url = url
            text = await Task.detached { store.readLog(at: url) }.value
        }
    }
}
