import AppKit
import SwiftUI

struct TaskEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ScriptTask

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $draft.name)
                Picker("脚本类型", selection: typeBinding) {
                    ForEach(ScriptType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("解释器", text: $draft.interpreterPath,
                          prompt: Text("默认：\(model.interpreterHint(for: draft.type))"))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    TextField("工作目录", text: $draft.workingDirectory, prompt: Text("默认：用户主目录"))
                        .font(.system(.body, design: .monospaced))
                    Button("选择…") { chooseDirectory() }
                }
                Toggle(isOn: $draft.useLoginShell) {
                    Text("使用登录 Shell 环境")
                    Text("通过 zsh -il 运行，加载 ~/.zprofile 和 ~/.zshrc 中的配置（如 conda、nvm、pyenv）")
                }
                Toggle("执行失败时发送系统通知", isOn: $draft.notifyOnFailure)
            }

            Section {
                CodeEditor(text: $draft.script)
                    .frame(minHeight: 240)
            } header: {
                Text("脚本")
            } footer: {
                Text("无需写 #! 首行，将使用上面的解释器执行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("执行时间") {
                ScheduleEditorView(schedule: $draft.schedule)
            }

            Section {
                ForEach($draft.environment) { $v in
                    HStack {
                        TextField("名称", text: $v.key, prompt: Text("变量名"))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 200)
                        Text("=").foregroundStyle(.secondary)
                        TextField("值", text: $v.value, prompt: Text("值"))
                            .font(.system(.body, design: .monospaced))
                        Button {
                            draft.environment.removeAll { $0.id == v.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .labelsHidden()
                }
                Button {
                    draft.environment.append(EnvVar())
                } label: {
                    Label("添加环境变量", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("环境变量")
            } footer: {
                Text("PATH 已自动设为你登录 Shell 的 PATH，可在此覆盖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// 切换脚本类型时，如果脚本还是默认模板就一起替换
    private var typeBinding: Binding<ScriptType> {
        Binding(
            get: { draft.type },
            set: { newType in
                let trimmed = draft.script.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == draft.type.template.trimmingCharacters(in: .whitespacesAndNewlines) {
                    draft.script = newType.template
                }
                draft.type = newType
            }
        )
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            draft.workingDirectory = url.path
        }
    }
}

/// 基于 NSTextView 的代码编辑器：关闭智能引号、自动替换、拼写检查，避免脚本被篡改
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
