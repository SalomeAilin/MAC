import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let permission = AccessibilityPermission.shared
    private let hotkeys = HotkeyCenter.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("权限") {
                PermissionRow(permission: permission)
            }

            Section("快捷键") {
                LabeledContent("翻译选中文字") {
                    ShortcutRecorder(combo: $settings.selectionHotkey, conflict: hotkeys.conflicts.contains(.translateSelection))
                }
                LabeledContent("输入翻译") {
                    ShortcutRecorder(combo: $settings.inputHotkey, conflict: hotkeys.conflicts.contains(.inputTranslation))
                }
            }

            Section {
                Picker("选中文字后", selection: $settings.selectionAction) {
                    ForEach(SelectionAction.allCases) { Text($0.title).tag($0) }
                }
                if settings.selectionAction != .off {
                    Picker("适用的文字", selection: $settings.autoTranslateScope) {
                        ForEach(AutoTranslateScope.allCases) { Text($0.title(primary: settings.primaryLanguage)).tag($0) }
                    }
                }
            } header: {
                Text("划词")
            } footer: {
                Text("选中其他文字时不会弹出，需要时按快捷键翻译。直接翻译时面板不会抢走键盘焦点，可以照常复制；继续打字、按 Esc 或点击别处时自动关闭。Chrome、VS Code 等 App 无法直接读取选区，会模拟一次 ⌘C 取得文字，随后自动恢复剪贴板。")
            }

            Section("语言") {
                Picker("翻译为", selection: $settings.primaryLanguageCode) {
                    ForEach(Language.all) { Text($0.name).tag($0.code) }
                }
                Picker("原文已是该语言时改译为", selection: $settings.secondaryLanguageCode) {
                    ForEach(Language.all) { Text($0.name).tag($0.code) }
                }
            }

            Section {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchError = nil
        } catch {
            launchError = "设置失败：\(error.localizedDescription)"
            launchAtLogin = service.status == .enabled
        }
    }
}

private struct PermissionRow: View {
    let permission: AccessibilityPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: permission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(permission.isGranted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.isGranted ? "辅助功能权限已开启" : "需要开启辅助功能权限")
                    Text(permission.isGranted ? "可以读取其他 App 中选中的文字" : "用于读取选中的文字和显示划词图标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !permission.isGranted {
                    Button("去开启…") { permission.request() }
                    Button("打开系统设置") { permission.openSystemSettings() }
                        .buttonStyle(.link)
                }
            }
            if !permission.isGranted {
                Text("在「系统设置 › 隐私与安全性 › 辅助功能」中打开 SelectTranslate。如果已经打开却仍显示未开启（重新编译后常见），选中它点「−」删除，再重新添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
