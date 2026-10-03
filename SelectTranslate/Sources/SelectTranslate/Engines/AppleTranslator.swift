import Foundation
@preconcurrency import Translation

/// macOS 内置的离线翻译（Translation 框架），免费、文本不出本机
final class AppleTranslator {
    static let shared = AppleTranslator()

    private var session: TranslationSession?
    private var sessionKey: String?
    private var requestGeneration: UInt64 = 0

    func translate(_ text: String, from source: Language, to target: Language, mode: AppleTranslationMode) async throws -> String {
        try Task.checkCancellation()
        requestGeneration &+= 1
        let generation = requestGeneration
        let status = await LanguageAvailability().status(from: source.localeLanguage, to: target.localeLanguage)
        try checkCurrentRequest(generation)
        switch status {
        case .installed:
            break
        case .supported:
            throw TranslationFailure.needsLanguageDownload(source: source, target: target)
        case .unsupported:
            throw TranslationFailure.unsupportedLanguagePair(source: source, target: target)
        @unknown default:
            break
        }

        let session = session(from: source, to: target, mode: mode)
        do {
            let response = try await session.translate(text)
            try checkCurrentRequest(generation)
            return response.targetText
        } catch TranslationError.notInstalled {
            try checkCurrentRequest(generation)
            reset(ifCurrent: session)
            throw TranslationFailure.needsLanguageDownload(source: source, target: target)
        } catch {
            try checkCurrentRequest(generation)
            if error is CancellationError { throw error }
            reset(ifCurrent: session)
            throw TranslationFailure.message("Apple 翻译出错：\(error.localizedDescription)")
        }
    }

    /// 同一语言对复用会话，避免每次重新加载模型
    private func session(from source: Language, to target: Language, mode: AppleTranslationMode) -> TranslationSession {
        let key = "\(source.code)>\(target.code)>\(mode.rawValue)"
        if let session, sessionKey == key { return session }
        reset()
        let created: TranslationSession
        if #available(macOS 26.4, *), mode != .automatic {
            created = TranslationSession(
                installedSource: source.localeLanguage,
                target: target.localeLanguage,
                preferredStrategy: mode == .highFidelity ? .highFidelity : .lowLatency
            )
        } else {
            created = TranslationSession(installedSource: source.localeLanguage, target: target.localeLanguage)
        }
        session = created
        sessionKey = key
        return created
    }

    private func reset() {
        session?.cancel()
        session = nil
        sessionKey = nil
    }

    private func reset(ifCurrent expected: TranslationSession) {
        guard session === expected else { return }
        reset()
    }

    private func checkCurrentRequest(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
    }

    static func languagePackStatus(_ source: Language, _ target: Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source.localeLanguage, to: target.localeLanguage)
    }
}
