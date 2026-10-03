import AppKit

/// 右键菜单 › 服务 › 用 SelectTranslate 翻译（不需要任何权限，几乎所有 App 都支持）
final class ServiceProvider: NSObject {
    var onText: ((String) -> Void)?

    // 方法名与 Info.plist 中 NSServices 的 NSMessage 对应
    @objc func translateText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isBlank else { return }
        onText?(text)
    }
}
