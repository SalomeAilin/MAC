import AppKit

let app = NSApplication.shared
#if DEBUG
// 预览只使用显式指定的资料目录，不启动划词监听、网络检查或 AI 请求。
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--preview-workspace" {
    print("Workspace preview PID: \(ProcessInfo.processInfo.processIdentifier)")
    let preview = WorkspaceWindowController(notesDirectory: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true), translate: { _ in })
    if preview.notes.document.notes.isEmpty {
        preview.notes.add(title: "今天的想法", body: "把今天值得留下的事情写在这里。\n\n网页摘录、截图和识别的文字都可以保存为笔记；需要总结或润色时，再把选定的内容交给 AI。")
    }
    _ = preview.notes.flush()
    preview.show()
    Task {
        try? await Task.sleep(for: .seconds(2))
        if let window = preview.window {
            // 只截本进程创建的预览窗口，普通视图缓存无法完整渲染 SwiftUI 的图层。
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), CommandLine.arguments[3]]
            do {
                try capture.run()
                print("Preview window capture PID: \(capture.processIdentifier)")
                capture.waitUntilExit()
                print("Preview capture exit: \(capture.terminationStatus)")
            } catch { print("Preview capture failed: \(error.localizedDescription)") }
        }
        _ = preview.prepareToClose()
        app.terminate(nil)
    }
    app.run()
    exit(0)
}
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
