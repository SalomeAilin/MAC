import AppKit
import Observation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let permission = AccessibilityPermission.shared
    private let panel = TranslationPanelController()
    private let selectionIcon = SelectionIconController()
    private let selectionMonitor = SelectionMonitor()
    private let serviceProvider = ServiceProvider()
    private var statusItem: StatusItemController?
    private var observations: [Task<Void, Never>] = []
    private var selectionRequest: Task<Void, Never>?
    private var selectionRequestID = UUID()
    private var iconSourceProcessID: pid_t?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(
            translateSelection: { [weak self] in self?.translateSelection() },
            inputTranslation: { [weak self] in self?.showInputTranslation() },
            translateClipboard: { [weak self] in self?.translateClipboard() }
        )

        panel.onOpenSettings = { SettingsWindowController.shared.show(tab: .engines) }
        selectionMonitor.onSelection = { [weak self] text, location, processID in
            self?.handleSelection(text, at: location, processID: processID)
        }
        selectionMonitor.onInterruption = { [weak self] in
            self?.cancelSelectionRequest()
            self?.selectionIcon.hide()
            self?.iconSourceProcessID = nil
        }
        selectionIcon.onClick = { [weak self] text, location in
            self?.translateFromIcon(text: text, at: location)
        }

        serviceProvider.onText = { [weak self] text in
            self?.cancelSelectionRequest()
            self?.panel.show(text: text, near: NSEvent.mouseLocation)
        }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelSelectionRequest()
                self?.selectionIcon.hide()
                self?.iconSourceProcessID = nil
            }
        }

        observeSettings()

        // 首次运行引导开启辅助功能权限（调试时可用 -SkipPermissionPrompt YES 跳过）
        if !permission.isGranted, !UserDefaults.standard.bool(forKey: "SkipPermissionPrompt") {
            permission.request()
            SettingsWindowController.shared.show(tab: .general)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    // MARK: - 触发方式

    /// 快捷键：读取当前选中的文字并翻译
    private func translateSelection() {
        cancelSelectionRequest()
        guard permission.isGranted else {
            permission.request()
            SettingsWindowController.shared.show(tab: .general)
            return
        }
        selectionIcon.hide()
        // 面板如果持有键盘焦点，读到的会是面板自己，先让焦点回到原 App
        if panel.isVisible { panel.hideTemporarily() }
        let location = NSEvent.mouseLocation
        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let requestID = selectionRequestID
        selectionRequest = Task {
            let text = await SelectionReader.read(processID: processID, allowClipboardFallback: true)
            guard isCurrentSelectionRequest(requestID, processID: processID) else { return }
            selectionRequest = nil
            if let text {
                panel.show(text: text, near: location)
            } else {
                panel.show(text: "", near: location, notice: "没有读取到选中的文字，可以直接在下面输入")
            }
        }
    }

    /// 鼠标选中文字之后：直接翻译，或显示翻译图标
    private func handleSelection(_ text: String?, at location: NSPoint, processID: pid_t) {
        cancelSelectionRequest()
        iconSourceProcessID = nil
        switch settings.selectionAction {
        case .off:
            return
        case .icon:
            iconSourceProcessID = processID
            selectionIcon.show(text: text, at: location)
        case .translate:
            let requestID = selectionRequestID
            selectionRequest = Task {
                // text 为 nil：浏览器、Electron 应用读不到 AX 选区，用 ⌘C 读取
                var text = text
                if text == nil { text = await SelectionReader.readViaClipboard(processID: processID) }
                guard isCurrentSelectionRequest(requestID, processID: processID, action: .translate) else { return }
                selectionRequest = nil
                guard let text, shouldAutoTranslate(text) else { return }
                selectionLog.notice("auto translate \(text.count, privacy: .public) chars")
                panel.show(text: text, near: location, passive: true)
            }
        }
    }

    private func shouldAutoTranslate(_ text: String) -> Bool {
        guard text.contains(where: \.isLetter) else {
            selectionLog.notice("skip: selection has no letters")
            return false
        }
        if settings.skipAutoTranslateForPrimary,
           LanguageDetector.detect(text).isSameLanguage(as: settings.primaryLanguage) {
            selectionLog.notice("skip: selection is already in the primary language")
            return false
        }
        return true
    }

    private func translateFromIcon(text: String?, at location: NSPoint) {
        cancelSelectionRequest()
        guard let processID = iconSourceProcessID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              settings.selectionAction == .icon
        else { return }
        iconSourceProcessID = nil
        if let text {
            panel.show(text: text, near: location)
            return
        }
        // 浏览器、Electron 应用：此时原 App 仍在前台，模拟 ⌘C 读取
        let requestID = selectionRequestID
        selectionRequest = Task {
            let text = await SelectionReader.readViaClipboard(processID: processID)
            guard isCurrentSelectionRequest(requestID, processID: processID, action: .icon) else { return }
            selectionRequest = nil
            if let text {
                panel.show(text: text, near: location)
            } else {
                panel.show(text: "", near: location, notice: "没有读取到选中的文字，可以直接在下面输入")
            }
        }
    }

    private func showInputTranslation() {
        cancelSelectionRequest()
        selectionIcon.hide()
        panel.show(text: "", near: NSEvent.mouseLocation)
    }

    private func translateClipboard() {
        cancelSelectionRequest()
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        panel.show(text: text, near: NSEvent.mouseLocation, notice: text.isBlank ? "剪贴板里没有文字" : nil)
    }

    // MARK: - 设置变化

    private func cancelSelectionRequest() {
        selectionRequest?.cancel()
        selectionRequest = nil
        selectionRequestID = UUID()
    }

    private func isCurrentSelectionRequest(_ requestID: UUID, processID: pid_t, action: SelectionAction? = nil) -> Bool {
        !Task.isCancelled && requestID == selectionRequestID
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
            && (action == nil || settings.selectionAction == action)
            && permission.isGranted
    }

    private func observeSettings() {
        observations.append(Task { [weak self] in
            for await combo in Observations({ AppSettings.shared.selectionHotkey }) {
                HotkeyCenter.shared.register(combo, for: .translateSelection) { self?.translateSelection() }
            }
        })
        observations.append(Task { [weak self] in
            for await combo in Observations({ AppSettings.shared.inputHotkey }) {
                HotkeyCenter.shared.register(combo, for: .inputTranslation) { self?.showInputTranslation() }
            }
        })
        // 划词需要辅助功能权限，并且可以在设置中关闭
        observations.append(Task { [weak self] in
            for await (action, granted) in Observations({
                (AppSettings.shared.selectionAction, AccessibilityPermission.shared.isGranted)
            }) {
                guard let self else { return }
                self.cancelSelectionRequest()
                self.selectionIcon.hide()
                self.iconSourceProcessID = nil
                selectionLog.notice("accessibility granted: \(AccessibilityPermission.shared.isGranted, privacy: .public), selection action: \(AppSettings.shared.selectionAction.rawValue, privacy: .public)")
                if action != .off && granted {
                    self.selectionMonitor.start()
                } else {
                    self.selectionMonitor.stop()
                    self.selectionIcon.hide()
                }
            }
        })
    }

    // MARK: - URL Scheme：selecttranslate://translate?text=…

    private func handle(_ url: URL) {
        guard url.scheme == "selecttranslate" else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let text = query?.first { $0.name == "text" }?.value ?? ""
        switch url.host() {
        case "translate":
            cancelSelectionRequest()
            panel.show(text: text, near: NSEvent.mouseLocation)
        case "selection":
            translateSelection()
        case "input":
            showInputTranslation()
        case "settings":
            cancelSelectionRequest()
            let tab: SettingsTab? = switch query?.first(where: { $0.name == "tab" })?.value {
            case "general": .general
            case "engines": .engines
            case "about": .about
            default: nil
            }
            SettingsWindowController.shared.show(tab: tab)
        #if DEBUG
        case "debug-snapshot":
            guard let path = query?.first(where: { $0.name == "path" })?.value else { return }
            let windowTitle = query?.first { $0.name == "window" }?.value
            if let windowTitle {
                NSApp.windows.first { $0.isVisible && $0.title.contains(windowTitle) }?.contentView?.debugSnapshot(to: path)
            } else {
                panel.debugSnapshot(to: path)
            }
        #endif
        default:
            break
        }
    }
}
