import SwiftUI

@main
struct ScriptTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("ScriptTimer", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { model.addTask() }
                    .keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.hasRecentFailure ? "exclamationmark.arrow.circlepath" : "timer")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 关闭主窗口后继续留在菜单栏
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
