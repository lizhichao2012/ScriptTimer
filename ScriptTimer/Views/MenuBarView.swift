import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let upcoming = model.upcoming(limit: 5)
        Section("即将执行") {
            if upcoming.isEmpty {
                Text("没有待执行的任务")
            } else {
                ForEach(upcoming, id: \.task.id) { item in
                    Text("\(item.date.runText)   \(item.task.name)")
                }
            }
        }

        let recent = model.recentRuns(limit: 5)
        if !recent.isEmpty {
            Section("最近执行") {
                ForEach(recent, id: \.record.id) { item in
                    Button {
                        model.selection = item.task.id
                        showMainWindow()
                    } label: {
                        Text("\(item.record.succeeded ? "✅" : "❌") \(item.record.startDate.runText)   \(item.task.name)")
                    }
                }
            }
        }

        if !model.tasks.isEmpty {
            Divider()
            Menu("立即运行") {
                ForEach(model.tasks) { task in
                    Button(task.name) { model.runNow(task.id) }
                }
            }
        }

        Divider()
        Button("打开 ScriptTimer…") { showMainWindow() }
            .keyboardShortcut("o")
        Toggle("开机时自动启动", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("退出（定时任务将停止）") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
