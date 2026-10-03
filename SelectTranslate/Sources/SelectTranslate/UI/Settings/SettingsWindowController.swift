import AppKit
import Observation
import SwiftUI

enum SettingsTab: Hashable {
    case general, engines, about
}

@Observable
final class SettingsRouter {
    var tab: SettingsTab = .general
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let router = SettingsRouter()
    private var window: NSWindow?

    func show(tab: SettingsTab? = nil) {
        if let tab { router.tab = tab }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(router: router)))
            window.title = "SelectTranslate 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("通用", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("翻译引擎", systemImage: "character.book.closed", value: SettingsTab.engines) {
                EngineSettingsView()
            }
            Tab("关于", systemImage: "info.circle", value: SettingsTab.about) {
                AboutView()
            }
        }
        .frame(width: 560, height: 620)
    }
}
