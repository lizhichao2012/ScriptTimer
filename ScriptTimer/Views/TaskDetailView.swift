import SwiftUI

struct TaskDetailView: View {
    enum Tab: Hashable { case edit, history }

    @Environment(AppModel.self) private var model
    let original: ScriptTask
    @State private var draft: ScriptTask
    @State private var tab: Tab = .edit

    init(task: ScriptTask) {
        original = task
        _draft = State(initialValue: task)
    }

    /// 是否有未保存的修改（启用状态由列表开关直接控制，不算在内）
    private var isDirty: Bool {
        var a = draft
        a.enabled = original.enabled
        a.completed = original.completed
        return a != original
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .edit:
                TaskEditorView(draft: $draft)
                Divider()
                footer
            case .history:
                HistoryView(task: original)
            }
        }
        .navigationTitle(original.name)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(original.name).font(.title3.weight(.semibold)).lineLimit(1)
                Text("\(original.schedule.summary) · \(model.statusText(original))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("视图", selection: $tab) {
                Text("编辑").tag(Tab.edit)
                Text("运行历史").tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Toggle("启用", isOn: Binding(
                get: { original.enabled },
                set: { model.setEnabled(original.id, $0) }
            ))
            .toggleStyle(.switch)
            .disabled(isDirty)
            .help(isDirty ? "请先保存修改" : "启用后，在 ScriptTimer 运行期间按设定时间自动执行")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button("删除…", role: .destructive) { model.deleteCandidate = original.id }
            Spacer()
            if isDirty {
                Text("有未保存的修改").font(.caption).foregroundStyle(.secondary)
                Button("还原") { draft = original }
            }
            Button("立即运行") {
                if isDirty, !save(enable: false) { return }
                model.runNow(original.id)
                tab = .history
            }
            .help("马上执行一次（未保存的修改会先保存）")
            .disabled(model.running.contains(original.id))
            if original.isActive {
                Button("保存") { save(enable: false) }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            } else {
                Button("仅保存") { save(enable: false) }
                    .disabled(!isDirty)
                Button("保存并启用") { save(enable: true) }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @discardableResult
    private func save(enable: Bool) -> Bool {
        guard model.save(draft, enable: enable) else { return false }
        if let saved = model.task(draft.id) { draft = saved }
        return true
    }
}
