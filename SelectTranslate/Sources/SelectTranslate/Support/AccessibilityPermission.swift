import AppKit
import ApplicationServices
import Observation

/// 辅助功能权限：读取其他 App 的选中文字、监听划词、模拟 ⌘C 都依赖它
@Observable
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isGranted = AXIsProcessTrusted()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private init() {
        // 用户在系统设置里切换开关时会发这个通知，但要稍等才能生效
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                AccessibilityPermission.shared.refresh()
            }
        }
        if !isGranted { startPolling() }
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isGranted { isGranted = granted }
        if !granted { startPolling() }
    }

    /// 弹出系统的授权提示（只在未授权时有效）
    func request() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        startPolling()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.isGranted = true
                    self.pollTask = nil
                    return
                }
            }
        }
    }
}
