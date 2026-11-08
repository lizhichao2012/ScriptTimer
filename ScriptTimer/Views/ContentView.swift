import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            TaskListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
        } detail: {
            if let id = model.selection, let task = model.task(id) {
                TaskDetailView(task: task)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("没有选中任务", systemImage: "timer")
                } description: {
                    Text("新建一个任务，填入脚本并设置执行时间。")
                } actions: {
                    Button("新建任务") { model.addTask() }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .alert("出错了", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "删除任务“\(model.deleteCandidate.flatMap { model.task($0)?.name } ?? "")”？",
            isPresented: Binding(
                get: { model.deleteCandidate != nil },
                set: { if !$0 { model.deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = model.deleteCandidate { model.delete(id) }
                model.deleteCandidate = nil
            }
        } message: {
            Text("任务设置和运行日志会被删除，脚本文件本身不受影响。")
        }
    }
}

struct TaskListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.tasks) { task in
                TaskRow(task: task)
                    .tag(task.id)
                    .contextMenu {
                        Button("立即运行") { model.runNow(task.id) }
                        Button(task.enabled ? "停用" : "启用") { model.setEnabled(task.id, !task.enabled) }
                        Divider()
                        Button("删除…", role: .destructive) { model.deleteCandidate = task.id }
                    }
            }
        }
        .overlay {
            if model.tasks.isEmpty {
                Text("还没有任务\n点右上角 + 新建")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label("任务仅在 ScriptTimer 运行时执行，关闭窗口后仍在菜单栏运行", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("开机时自动启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .font(.caption)
                .toggleStyle(.checkbox)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem {
                Button { model.addTask() } label: { Label("新建任务", systemImage: "plus") }
                    .help("新建任务 (⌘N)")
            }
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: ScriptTask

    var body: some View {
        HStack(spacing: 10) {
            if model.running.contains(task.id) {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 8, height: 8)
                    .help("运行中")
            } else {
                StatusDot(record: model.lastRecord(task))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .lineLimit(1)
                    .foregroundStyle(task.isActive ? .primary : .secondary)
                Text(task.schedule.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.statusText(task))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("启用", isOn: Binding(
                get: { task.enabled },
                set: { model.setEnabled(task.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}

/// 最近一次执行结果：绿=成功，红=失败，灰=未执行过
struct StatusDot: View {
    let record: RunRecord?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(help)
    }

    private var color: Color {
        guard let record else { return .gray.opacity(0.4) }
        return record.succeeded ? .green : .red
    }

    private var help: String {
        guard let record else { return "尚未执行" }
        return "\(record.startDate.runText) · 退出码 \(record.exitCode)"
    }
}
