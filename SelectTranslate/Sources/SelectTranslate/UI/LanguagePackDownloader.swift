import AppKit
import SwiftUI
@preconcurrency import Translation

/// 通过系统的下载确认流程获取 Apple 翻译的离线语言包
final class LanguagePackDownloader {
    static let shared = LanguagePackDownloader()

    private var window: NSWindow?

    func present(source: Language, target: Language, onInstalled: @escaping () -> Void) {
        window?.close()
        let view = LanguagePackDownloadView(source: source, target: target) { [weak self] installed in
            self?.window?.close()
            self?.window = nil
            if installed { onInstalled() }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "下载离线语言包"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct LanguagePackDownloadView: View {
    let source: Language
    let target: Language
    let onFinish: (Bool) -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("下载「\(source.name) ↔ \(target.name)」语言包", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("Apple 翻译在本机离线运行，首次使用这组语言需要先下载语言包。点击「下载」后系统会弹出确认，下载完成后自动继续翻译。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("在系统设置中管理") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                Spacer()
                Button("取消") { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("下载") {
                    isWorking = true
                    message = "等待系统确认并下载…"
                    configuration = TranslationSession.Configuration(source: source.localeLanguage, target: target.localeLanguage)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 440)
        .translationTask(configuration) { session in
            do {
                // 未安装时会弹出系统的下载确认，并等待下载完成
                try await session.prepareTranslation()
                message = "下载完成"
                onFinish(true)
            } catch {
                message = "没有完成下载：\(error.localizedDescription)"
                isWorking = false
            }
        }
    }
}
