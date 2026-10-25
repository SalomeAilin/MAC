import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let notes: WorkspaceNotes
    let assistant = WorkspaceAssistant()
    let browser = WorkspaceBrowser()
    let network = WorkspaceNetwork()
    let capture = WorkspaceCapture()

    init(notesDirectory: URL? = nil, translate: @escaping (String) -> Void) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        notes = WorkspaceNotes(repository: WorkspaceNotesRepository(
            directory: notesDirectory ?? support.appendingPathComponent("com.alsay.SelectTranslate/Workspace", isDirectory: true)
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "工作台"
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        if notesDirectory == nil { window.setFrameAutosaveName("WorkspaceWindow") }
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WorkspaceView(controller: self, translate: translate))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func takeScreenshot() {
        capture.capture(into: notes, hide: { [weak self] in self?.window?.orderOut(nil) }, restore: { [weak self] in self?.show() })
    }

    func exportCurrentText() {
        guard let note = notes.selectedNote else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "笔记.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try (note.title + "\n\n" + note.body).write(to: url, atomically: true, encoding: .utf8) }
        catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func prepareToClose() -> Bool {
        guard notes.flush() else {
            let alert = NSAlert()
            alert.messageText = "笔记尚未保存"
            alert.informativeText = (notes.error ?? "保存失败") + "\n请先导出当前正文，再处理文件问题。"
            alert.runModal()
            return false
        }
        assistant.stop()
        network.cancel()
        capture.cancel()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { prepareToClose() }
    func windowWillClose(_ notification: Notification) {
        browser.closeSession()
        NSApp.setActivationPolicy(.accessory)
    }
}
