import Foundation

/// 翻译失败的原因；部分原因在界面上会给出对应的操作按钮
nonisolated enum TranslationFailure: Error, Equatable, Sendable {
    case needsLanguageDownload(source: Language, target: Language)
    case unsupportedLanguagePair(source: Language, target: Language)
    case missingAPIKey
    case message(String)

    var description: String {
        switch self {
        case .needsLanguageDownload(let source, let target):
            "需要先下载「\(source.name) ↔ \(target.name)」离线语言包"
        case .unsupportedLanguagePair(let source, let target):
            "Apple 翻译暂不支持 \(source.name) → \(target.name)"
        case .missingAPIKey:
            "还没有设置 Claude API Key"
        case .message(let message):
            message
        }
    }
}
