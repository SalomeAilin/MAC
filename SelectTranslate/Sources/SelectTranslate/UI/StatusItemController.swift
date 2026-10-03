import AppKit

/// 菜单栏图标和菜单
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let translateSelection: () -> Void
    private let inputTranslation: () -> Void
    private let translateClipboard: () -> Void

    init(translateSelection: @escaping () -> Void,
         inputTranslation: @escaping () -> Void,
         translateClipboard: @escaping () -> Void) {
        self.translateSelection = translateSelection
        self.inputTranslation = inputTranslation
        self.translateClipboard = translateClipboard
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "SelectTranslate")
        statusItem.button?.toolTip = "SelectTranslate 选中翻译"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // 每次打开菜单时按最新设置重建
    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        menu.removeAllItems()
        menu.addItem(item("翻译选中文字", hotkey: settings.selectionHotkey, action: #selector(onTranslateSelection)))
        menu.addItem(item("输入翻译", hotkey: settings.inputHotkey, action: #selector(onInputTranslation)))
        menu.addItem(item("翻译剪贴板", action: #selector(onTranslateClipboard)))
        menu.addItem(.separator())

        menu.addItem(selectionActionItem(current: settings.selectionAction, scope: settings.autoTranslateScope, primary: settings.primaryLanguage))
        menu.addItem(targetLanguageItem(current: settings.primaryLanguageCode))
        menu.addItem(.separator())

        if !AccessibilityPermission.shared.isGranted {
            menu.addItem(item("开启辅助功能权限…", action: #selector(onGrantPermission)))
        }
        menu.addItem(item("设置…", key: ",", action: #selector(onOpenSettings)))
        menu.addItem(item("退出 SelectTranslate", key: "q", action: #selector(onQuit)))
    }

    private func item(_ title: String, key: String = "", hotkey: KeyCombo? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let hotkey {
            // 菜单里只用来展示全局快捷键
            let name = KeyCombo.keyName(for: Int(hotkey.keyCode))
            if name.count == 1 {
                item.keyEquivalent = name.lowercased()
                item.keyEquivalentModifierMask = hotkey.modifiers
            } else {
                item.title += "    \(hotkey.displayString)"
            }
        }
        return item
    }

    private func selectionActionItem(current: SelectionAction, scope: AutoTranslateScope, primary: Language) -> NSMenuItem {
        let item = NSMenuItem(title: "选中文字后：\(current.title)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for action in SelectionAction.allCases {
            let entry = NSMenuItem(title: action.title, action: #selector(onSelectAction(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            entry.state = action == current ? .on : .off
            submenu.addItem(entry)
        }
        if current != .off {
            submenu.addItem(.separator())
            submenu.addItem(.sectionHeader(title: "适用的文字"))
            for option in AutoTranslateScope.allCases {
                let entry = NSMenuItem(title: option.title(primary: primary), action: #selector(onSelectScope(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = option.rawValue
                entry.state = option == scope ? .on : .off
                submenu.addItem(entry)
            }
        }
        item.submenu = submenu
        return item
    }

    private func targetLanguageItem(current: String) -> NSMenuItem {
        let item = NSMenuItem(title: "翻译为", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in Language.all {
            let entry = NSMenuItem(title: language.name, action: #selector(onSelectLanguage(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = language.code
            entry.state = language.code == current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    @objc private func onTranslateSelection() { translateSelection() }
    @objc private func onInputTranslation() { inputTranslation() }
    @objc private func onTranslateClipboard() { translateClipboard() }
    @objc private func onSelectAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = SelectionAction(rawValue: raw) else { return }
        AppSettings.shared.selectionAction = action
    }
    @objc private func onSelectScope(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let scope = AutoTranslateScope(rawValue: raw) else { return }
        AppSettings.shared.autoTranslateScope = scope
    }
    @objc private func onGrantPermission() {
        AccessibilityPermission.shared.request()
        SettingsWindowController.shared.show(tab: .general)
    }
    @objc private func onOpenSettings() { SettingsWindowController.shared.show() }
    @objc private func onQuit() { NSApp.terminate(nil) }

    @objc private func onSelectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        AppSettings.shared.primaryLanguageCode = code
    }
}
