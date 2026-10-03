import Foundation
import Observation

nonisolated enum EngineKind: String, Sendable {
    case apple, claude

    var title: String {
        switch self {
        case .apple: "Apple 翻译"
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        case .claude: "sparkle"
        }
    }
}

/// 一个翻译引擎的结果卡片
@Observable
final class EngineResult: Identifiable {
    enum State: Equatable {
        case loading
        case streaming(String)
        case finished(String)
        case failed(TranslationFailure)
    }

    let kind: EngineKind
    var state: State = .loading
    var id: EngineKind { kind }

    init(kind: EngineKind) { self.kind = kind }

    var isBusy: Bool {
        switch state {
        case .loading, .streaming: true
        default: false
        }
    }

    var text: String? {
        switch state {
        case .streaming(let text), .finished(let text): text
        default: nil
        }
    }
}

@Observable
final class TranslationViewModel {
    static let maxLength = 8000

    var sourceText = ""
    /// nil 表示自动检测
    private(set) var sourceOverride: Language?
    private(set) var detectedLanguage: Language?
    /// nil 表示按设置自动决定（中英互译）
    private(set) var targetOverride: Language?
    private(set) var targetLanguage: Language = AppSettings.shared.primaryLanguage
    private(set) var results: [EngineResult] = []
    private(set) var dictionaryEntry: DictionaryEntry?
    var notice: String?
    var isPinned = false
    /// 递增即请求聚焦输入框
    private(set) var focusRequest = 0

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var debounce: Task<Void, Never>?

    var sourceLanguage: Language? { sourceOverride ?? detectedLanguage }

    func load(text: String, notice: String? = nil) {
        var text = text
        self.notice = notice
        if text.count > Self.maxLength {
            text = String(text.prefix(Self.maxLength))
            self.notice = "文字较长，只翻译了前 \(Self.maxLength) 个字符"
        }
        sourceText = text
        sourceOverride = nil
        targetOverride = nil
        translate()
    }

    func requestFocus() {
        focusRequest += 1
    }

    func setSource(_ language: Language?) {
        sourceOverride = language
        translate()
    }

    func setTarget(_ language: Language) {
        targetOverride = language
        translate()
    }

    /// 在输入框里编辑时，停顿一会儿再翻译
    func scheduleTranslate() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            translate()
        }
    }

    func translate() {
        cancel()
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            dictionaryEntry = nil
            detectedLanguage = nil
            return
        }

        let settings = AppSettings.shared
        let detected = LanguageDetector.detect(text)
        detectedLanguage = detected
        let source = sourceOverride ?? detected
        let target = targetOverride
            ?? LanguageDetector.target(for: source, primary: settings.primaryLanguage, secondary: settings.secondaryLanguage)
        targetLanguage = target
        dictionaryEntry = nil

        var engines: [EngineKind] = []
        if settings.appleEnabled { engines.append(.apple) }
        if settings.claudeEnabled { engines.append(.claude) }
        results = engines.map(EngineResult.init)
        for result in results {
            tasks.append(Task { await run(result, text: text, source: source, target: target) })
        }

        if settings.dictionaryEnabled, SystemDictionary.shouldLookUp(text, language: source) {
            tasks.append(Task {
                let entry = await SystemDictionary.lookUp(text)
                guard !Task.isCancelled else { return }
                dictionaryEntry = entry
            })
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        debounce?.cancel()
    }

    private func run(_ result: EngineResult, text: String, source: Language, target: Language) async {
        let settings = AppSettings.shared
        do {
            switch result.kind {
            case .apple:
                let output = try await AppleTranslator.shared.translate(text, from: source, to: target, mode: settings.appleMode)
                guard !Task.isCancelled else { return }
                result.state = .finished(output)
            case .claude:
                guard let apiKey = settings.anthropicAPIKey else { throw TranslationFailure.missingAPIKey }
                var output = ""
                try await ClaudeTranslator.translate(
                    text, from: source, to: target,
                    model: settings.claudeModel, effort: settings.claudeEffort, apiKey: apiKey
                ) { delta in
                    output += delta
                    result.state = .streaming(output)
                }
                guard !Task.isCancelled else { return }
                result.state = .finished(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            result.state = .failed(error as? TranslationFailure ?? .message(error.localizedDescription))
        }
    }
}
