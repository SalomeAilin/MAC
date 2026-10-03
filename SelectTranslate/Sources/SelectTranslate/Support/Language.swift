import Foundation
import NaturalLanguage

/// 支持的语言，与 Apple 翻译框架支持的语言保持一致
nonisolated struct Language: Hashable, Identifiable, Sendable {
    let code: String          // BCP-47，如 "zh-Hans"、"en"
    let name: String          // 界面显示的中文名
    let englishName: String   // 写给大模型的语言名
    let speechCode: String    // 朗读时使用的语音区域

    var id: String { code }
    var localeLanguage: Locale.Language { Locale.Language(identifier: code) }
    var baseCode: String { String(code.prefix { $0 != "-" }) }

    /// 简繁中文视为同一种语言（用于判断"原文已经是目标语言"）
    func isSameLanguage(as other: Language) -> Bool { baseCode == other.baseCode }

    static let simplifiedChinese = Language(code: "zh-Hans", name: "简体中文", englishName: "Simplified Chinese", speechCode: "zh-CN")
    static let traditionalChinese = Language(code: "zh-Hant", name: "繁体中文", englishName: "Traditional Chinese", speechCode: "zh-TW")
    static let english = Language(code: "en", name: "英语", englishName: "English", speechCode: "en-US")
    static let japanese = Language(code: "ja", name: "日语", englishName: "Japanese", speechCode: "ja-JP")
    static let korean = Language(code: "ko", name: "韩语", englishName: "Korean", speechCode: "ko-KR")

    static let all: [Language] = [
        .simplifiedChinese, .traditionalChinese, .english, .japanese, .korean,
        Language(code: "fr", name: "法语", englishName: "French", speechCode: "fr-FR"),
        Language(code: "de", name: "德语", englishName: "German", speechCode: "de-DE"),
        Language(code: "es", name: "西班牙语", englishName: "Spanish", speechCode: "es-ES"),
        Language(code: "it", name: "意大利语", englishName: "Italian", speechCode: "it-IT"),
        Language(code: "pt", name: "葡萄牙语", englishName: "Portuguese", speechCode: "pt-BR"),
        Language(code: "ru", name: "俄语", englishName: "Russian", speechCode: "ru-RU"),
        Language(code: "ar", name: "阿拉伯语", englishName: "Arabic", speechCode: "ar-SA"),
        Language(code: "th", name: "泰语", englishName: "Thai", speechCode: "th-TH"),
        Language(code: "vi", name: "越南语", englishName: "Vietnamese", speechCode: "vi-VN"),
        Language(code: "id", name: "印尼语", englishName: "Indonesian", speechCode: "id-ID"),
        Language(code: "tr", name: "土耳其语", englishName: "Turkish", speechCode: "tr-TR"),
        Language(code: "pl", name: "波兰语", englishName: "Polish", speechCode: "pl-PL"),
        Language(code: "nl", name: "荷兰语", englishName: "Dutch", speechCode: "nl-NL"),
        Language(code: "uk", name: "乌克兰语", englishName: "Ukrainian", speechCode: "uk-UA"),
        Language(code: "hi", name: "印地语", englishName: "Hindi", speechCode: "hi-IN"),
    ]

    static func find(_ code: String) -> Language? { all.first { $0.code == code } }

    /// 根据系统首选语言推断默认的目标语言
    static var systemPreferred: Language {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            let traditional = ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"].contains { preferred.hasPrefix($0) }
            return traditional ? .traditionalChinese : .simplifiedChinese
        }
        let base = String(preferred.prefix { $0 != "-" })
        return find(base) ?? .english
    }
}

/// 语种识别：先按文字系统快速判断中日韩，再交给 NaturalLanguage
nonisolated enum LanguageDetector {
    static func detect(_ text: String) -> Language {
        let sample = String(text.prefix(1500))
        var han = 0, kana = 0, hangul = 0, latin = 0
        for scalar in sample.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: han += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: latin += 1
            default: break
            }
        }
        // 日文几乎总会夹带假名；中文里偶尔出现的"の"不算
        if kana > 0, kana * 8 >= han, (kana + han) * 2 >= latin { return .japanese }
        if hangul > 0, hangul * 2 >= latin { return .korean }
        if han > 0, han * 2 >= latin { return chineseVariant(of: sample, hanCount: han) }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Language.all.map { NLLanguage(rawValue: $0.code) }
        recognizer.processString(sample)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value }),
              let language = Language.find(best.rawValue)
        else { return .english }
        // 很短的纯 ASCII 文本识别不可靠（如 "OK"），没有把握时按英语处理
        if confidence < 0.75, sample.unicodeScalars.allSatisfy(\.isASCII) { return .english }
        return language
    }

    /// 简繁判断：把文本转换成简体，变化的字足够多就是繁体
    private static func chineseVariant(of text: String, hanCount: Int) -> Language {
        guard let simplified = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) else {
            return .simplifiedChinese
        }
        let changed = zip(text, simplified).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        return changed >= max(1, hanCount / 20) ? .traditionalChinese : .simplifiedChinese
    }

    /// 原文已经是首选目标语言时，改译为第二语言（实现"中英互译"）
    static func target(for source: Language, primary: Language, secondary: Language) -> Language {
        source.isSameLanguage(as: primary) ? secondary : primary
    }
}
