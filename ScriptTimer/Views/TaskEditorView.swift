import AppKit
import SwiftUI

struct TaskEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ScriptTask

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("脚本路径", text: $draft.scriptPath, prompt: Text("输入路径，或点右侧按钮选择，也可以把文件拖到这里"))
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { detectType() }
                    Button("选择…") { chooseScript() }
                }
                if let problem = draft.scriptProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(draft.scriptPath.isEmpty ? Color.secondary : Color.red)
                } else {
                    HStack {
                        Label("文件可用", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: draft.resolvedScriptPath)])
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    ScriptPreview(path: draft.resolvedScriptPath)
                }
            } header: {
                Text("脚本文件")
            } footer: {
                Text("ScriptTimer 只记录路径，每次执行都会读取文件的最新内容；删除任务不会删除脚本文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.isFileURL else { return false }
                setScript(url.path)
                return true
            }

            Section("基本信息") {
                TextField("名称", text: $draft.name)
                Picker("脚本类型", selection: $draft.type) {
                    ForEach(ScriptType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("解释器", text: $draft.interpreterPath,
                          prompt: Text("默认：\(model.interpreterHint(for: draft.type))"))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    TextField("工作目录", text: $draft.workingDirectory, prompt: Text("默认：脚本所在目录"))
                        .font(.system(.body, design: .monospaced))
                    Button("选择…") { chooseDirectory() }
                }
                Toggle(isOn: $draft.useLoginShell) {
                    Text("使用登录 Shell 环境")
                    Text("通过 zsh -il 运行，加载 ~/.zprofile 和 ~/.zshrc 中的配置（如 conda、nvm、pyenv）")
                }
                Toggle("执行失败时发送系统通知", isOn: $draft.notifyOnFailure)
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

    // MARK: - 选择脚本

    private func setScript(_ path: String) {
        draft.scriptPath = (path as NSString).abbreviatingWithTildeInPath
        detectType()
        // 名称还是默认值时，用文件名代替
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.hasPrefix("新任务") {
            draft.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
    }

    private func detectType() {
        let path = draft.resolvedScriptPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        draft.type = ScriptType.detect(fileAt: path)
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择要定时执行的脚本（.sh / .zsh / .bash / .py 等）"
        let current = draft.resolvedScriptPath
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            setScript(url.path)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            draft.workingDirectory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

/// 脚本内容只读预览（前 200 行）
struct ScriptPreview: View {
    let path: String
    @State private var text = ""

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? "（空文件）" : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
        }
        .frame(height: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .task(id: path) {
            let path = path
            text = await Task.detached { Self.load(path) }.value
        }
    }

    nonisolated private static func load(_ path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let content = String(decoding: data, as: UTF8.self)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 200 {
            return lines.prefix(200).joined(separator: "\n") + "\n…"
        }
        return content
    }
}
