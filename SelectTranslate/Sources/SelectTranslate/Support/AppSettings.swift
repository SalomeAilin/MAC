import Foundation
import Observation

/// 用鼠标选中文字之后做什么
nonisolated enum SelectionAction: String, CaseIterable, Identifiable, Sendable {
    case translate, icon, off

    var id: Self { self }
    var title: String {
        switch self {
        case .translate: "直接翻译"
        case .icon: "显示翻译图标"
        case .off: "不处理（只用快捷键）"
        }
    }
}

/// 选中哪些语言的文字时才自动翻译（或显示图标）；快捷键不受限制
nonisolated enum AutoTranslateScope: String, CaseIterable, Identifiable, Sendable {
    case english, nonPrimary, all

    var id: Self { self }

    func title(primary: Language) -> String {
        switch self {
        case .english: "只有英文"
        case .nonPrimary: "除\(primary.name)以外的文字"
        case .all: "所有文字"
        }
    }

    func allows(_ language: Language, primary: Language) -> Bool {
        switch self {
        case .english: language == .english
        case .nonPrimary: !language.isSameLanguage(as: primary)
        case .all: true
        }
    }
}

nonisolated enum AppleTranslationMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, highFidelity, lowLatency

    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: "系统默认"
        case .highFidelity: "高质量"
        case .lowLatency: "低延迟"
        }
    }
}

nonisolated enum ClaudeModel: String, CaseIterable, Identifiable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-4-5"

    var id: Self { self }
    var title: String {
        switch self {
        case .opus: "Claude Opus 5.5（质量最好）"
        case .sonnet: "Claude Sonnet 5.5（均衡）"
        case .haiku: "Claude Haiku 4.5（最快最省）"
        }
    }
    /// Haiku 4.5 不支持 effort 参数
    var supportsEffort: Bool { self != .haiku }
    /// 服务端拒答回退只适用于带安全分类器的新模型
    var supportsFallbacks: Bool { self != .haiku }
}

nonisolated enum ClaudeEffort: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: Self { self }
    var title: String {
        switch self {
        case .low: "低（响应最快）"
        case .medium: "中"
        case .high: "高"
        }
    }
}

/// 所有用户设置，存于 UserDefaults；API Key 单独存钥匙串
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var primaryLanguageCode: String { didSet { defaults.set(primaryLanguageCode, forKey: Key.primaryLanguage) } }
    var secondaryLanguageCode: String { didSet { defaults.set(secondaryLanguageCode, forKey: Key.secondaryLanguage) } }
    var selectionAction: SelectionAction { didSet { defaults.set(selectionAction.rawValue, forKey: Key.selectionAction) } }
    var autoTranslateScope: AutoTranslateScope { didSet { defaults.set(autoTranslateScope.rawValue, forKey: Key.autoTranslateScope) } }
    var selectionHotkey: KeyCombo? { didSet { saveHotkey(selectionHotkey, forKey: Key.selectionHotkey) } }
    var inputHotkey: KeyCombo? { didSet { saveHotkey(inputHotkey, forKey: Key.inputHotkey) } }
    var googleEnabled: Bool { didSet { defaults.set(googleEnabled, forKey: Key.googleEnabled) } }
    var appleEnabled: Bool { didSet { defaults.set(appleEnabled, forKey: Key.appleEnabled) } }
    var appleMode: AppleTranslationMode { didSet { defaults.set(appleMode.rawValue, forKey: Key.appleMode) } }
    var dictionaryEnabled: Bool { didSet { defaults.set(dictionaryEnabled, forKey: Key.dictionaryEnabled) } }
    var claudeEnabled: Bool { didSet { defaults.set(claudeEnabled, forKey: Key.claudeEnabled) } }
    var claudeModel: ClaudeModel { didSet { defaults.set(claudeModel.rawValue, forKey: Key.claudeModel) } }
    var claudeEffort: ClaudeEffort { didSet { defaults.set(claudeEffort.rawValue, forKey: Key.claudeEffort) } }
    private(set) var hasAnthropicAPIKey: Bool

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var cachedAPIKey: String?

    var primaryLanguage: Language { Language.find(primaryLanguageCode) ?? .simplifiedChinese }
    var secondaryLanguage: Language { Language.find(secondaryLanguageCode) ?? .english }

    /// 首次读取后缓存，避免每次翻译都访问钥匙串
    var anthropicAPIKey: String? {
        if cachedAPIKey == nil { cachedAPIKey = Keychain.string(for: Key.anthropicAPIKey) }
        return cachedAPIKey
    }

    func setAnthropicAPIKey(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard Keychain.set(value, for: Key.anthropicAPIKey) else { return false }
        cachedAPIKey = value
        hasAnthropicAPIKey = value != nil
        return true
    }

    private init() {
        let defaults = UserDefaults.standard
        let preferred = Language.systemPreferred
        let primaryCode = defaults.string(forKey: Key.primaryLanguage) ?? preferred.code
        primaryLanguageCode = primaryCode
        secondaryLanguageCode = defaults.string(forKey: Key.secondaryLanguage)
            ?? (preferred == .english ? Language.simplifiedChinese.code : Language.english.code)
        selectionAction = defaults.string(forKey: Key.selectionAction).flatMap(SelectionAction.init) ?? .translate
        // 默认只在选中外文时弹出：中文用户只翻英文，英文用户翻译其他语言
        autoTranslateScope = defaults.string(forKey: Key.autoTranslateScope).flatMap(AutoTranslateScope.init)
            ?? (Language.find(primaryCode) == .english ? .nonPrimary : .english)
        selectionHotkey = Self.loadHotkey(forKey: Key.selectionHotkey, default: .defaultSelection)
        inputHotkey = Self.loadHotkey(forKey: Key.inputHotkey, default: .defaultInput)
        googleEnabled = defaults.object(forKey: Key.googleEnabled) as? Bool ?? true
        appleEnabled = defaults.object(forKey: Key.appleEnabled) as? Bool ?? true
        appleMode = defaults.string(forKey: Key.appleMode).flatMap(AppleTranslationMode.init) ?? .automatic
        dictionaryEnabled = defaults.object(forKey: Key.dictionaryEnabled) as? Bool ?? true
        claudeEnabled = defaults.object(forKey: Key.claudeEnabled) as? Bool ?? false
        claudeModel = defaults.string(forKey: Key.claudeModel).flatMap(ClaudeModel.init) ?? .opus
        claudeEffort = defaults.string(forKey: Key.claudeEffort).flatMap(ClaudeEffort.init) ?? .low
        hasAnthropicAPIKey = Keychain.string(for: Key.anthropicAPIKey) != nil
    }

    // 快捷键：没有存过用默认值；存了空数据表示用户清除了快捷键
    private static func loadHotkey(forKey key: String, default fallback: KeyCombo) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        guard !data.isEmpty else { return nil }
        return (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? fallback
    }

    private func saveHotkey(_ combo: KeyCombo?, forKey key: String) {
        let data = combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: key)
    }

    private enum Key {
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let selectionAction = "selectionAction"
        static let autoTranslateScope = "autoTranslateScope"
        static let selectionHotkey = "selectionHotkey"
        static let inputHotkey = "inputHotkey"
        static let googleEnabled = "googleEnabled"
        static let appleEnabled = "appleEnabled"
        static let appleMode = "appleMode"
        static let dictionaryEnabled = "dictionaryEnabled"
        static let claudeEnabled = "claudeEnabled"
        static let claudeModel = "claudeModel"
        static let claudeEffort = "claudeEffort"
        static let anthropicAPIKey = "anthropic-api-key"
    }
}
