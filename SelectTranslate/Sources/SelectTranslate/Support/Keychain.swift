import Foundation
import Security

/// 把 API Key 存在登录钥匙串里，而不是明文写进偏好设置
nonisolated enum Keychain {
    private static let service = "com.alsay.SelectTranslate"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 传入 nil 或空字符串表示删除
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let updates: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrLabel as String: "SelectTranslate (\(account))",
        ]
        let status = SecItemUpdate(base as CFDictionary, updates as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        let attributes = base.merging(updates) { _, value in value }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
