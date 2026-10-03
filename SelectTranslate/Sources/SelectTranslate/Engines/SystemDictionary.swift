import Foundation
import NaturalLanguage

/// 一条整理过的词典释义
nonisolated struct DictionaryEntry: Equatable, Sendable {
    struct Pronunciation: Equatable, Sendable {
        let label: String          // 英 / 美
        let ipa: String
        let voiceLanguage: String  // en-GB / en-US
    }

    struct Line: Identifiable, Equatable, Sendable {
        enum Kind: Sendable { case section, sense, example, plain }
        let id: Int
        let kind: Kind
        let text: String
    }

    let dictionaryName: String
    let headword: String
    let pronunciations: [Pronunciation]
    let lines: [Line]
    var note: String?   // 例如 "ran 是 run 的过去式"
}

/// 查询「词典」App 中启用的词典（如牛津英汉汉英词典）
nonisolated enum SystemDictionary {
    /// 只对英文单词和短语（不超过 3 个词）查词典
    static func shouldLookUp(_ text: String, language: Language) -> Bool {
        guard language == .english else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count), trimmed.split(whereSeparator: \.isWhitespace).count <= 3 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" || $0 == "’" }
    }

    static func lookUp(_ text: String) async -> DictionaryEntry? {
        guard let api = DictionaryServicesAPI.shared else { return nil }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var candidates = [query]
        if query.lowercased() != query { candidates.append(query.lowercased()) }

        for candidate in candidates {
            guard let entry = api.entry(for: candidate) else { continue }
            // "ran | … | past tense → run A, B" 这种只有指向的条目，换成原形的完整释义
            if entry.isCrossReference,
               let base = entry.crossReferenceTarget ?? lemma(of: candidate), base != candidate,
               var full = api.entry(for: base) {
                full.note = "\(entry.headword)：" + entry.lines.map(\.text).joined(separator: " ")
                return full
            }
            return entry
        }
        if let lemma = lemma(of: query), !candidates.contains(lemma) {
            return api.entry(for: lemma)
        }
        return nil
    }

    /// 词形还原：running → run，ran → run
    private static func lemma(of word: String) -> String? {
        guard !word.contains(" ") else { return nil }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        // 单个词无法自动识别语言，不指定时取不到原形
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        guard let lemma = tag?.rawValue.lowercased(), !lemma.isEmpty, lemma != word.lowercased() else { return nil }
        return lemma
    }
}

private extension DictionaryEntry {
    nonisolated var isCrossReference: Bool {
        let body = lines.map(\.text).joined(separator: " ")
        return body.contains("→") && body.count < 80
    }

    /// "past tense → run A, B" 中箭头指向的词
    nonisolated var crossReferenceTarget: String? {
        let body = lines.map(\.text).joined(separator: " ")
        guard let range = body.range(of: #"→\s*[A-Za-z][A-Za-z'-]*"#, options: .regularExpression) else { return nil }
        return body[range].dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// DictionaryServices 的私有接口（公开的 DCSCopyTextDefinition 会把 "run" 匹配成拼音 rùn）
private nonisolated final class DictionaryServicesAPI: @unchecked Sendable {
    static let shared = DictionaryServicesAPI()

    private typealias GetActiveDictionaries = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetDictionaryName = @convention(c) (CFTypeRef) -> Unmanaged<CFString>?
    private typealias CopyRecords = @convention(c) (CFTypeRef, CFString, UInt64, Int64) -> Unmanaged<CFArray>?
    private typealias GetHeadword = @convention(c) (CFTypeRef) -> Unmanaged<CFString>?
    private typealias CopyRecordData = @convention(c) (CFTypeRef, Int64) -> Unmanaged<CFTypeRef>?

    private let activeDictionaries: GetActiveDictionaries
    private let dictionaryName: GetDictionaryName
    private let copyRecords: CopyRecords
    private let headword: GetHeadword
    private let copyRecordData: CopyRecordData

    private static let exactMatch: UInt64 = 0
    private static let plainTextVersion: Int64 = 3

    private init?() {
        let path = "/System/Library/Frameworks/CoreServices.framework/Frameworks/DictionaryServices.framework/DictionaryServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func load<T>(_ symbol: String, as type: T.Type) -> T? {
            dlsym(handle, symbol).map { unsafeBitCast($0, to: type) }
        }
        guard let activeDictionaries = load("DCSGetActiveDictionaries", as: GetActiveDictionaries.self),
              let dictionaryName = load("DCSDictionaryGetName", as: GetDictionaryName.self),
              let copyRecords = load("DCSCopyRecordsForSearchString", as: CopyRecords.self),
              let headword = load("DCSRecordGetHeadword", as: GetHeadword.self),
              let copyRecordData = load("DCSRecordCopyData", as: CopyRecordData.self)
        else { return nil }
        self.activeDictionaries = activeDictionaries
        self.dictionaryName = dictionaryName
        self.copyRecords = copyRecords
        self.headword = headword
        self.copyRecordData = copyRecordData
    }

    /// 按「词典」App 中的顺序查找词条完全匹配的第一本词典
    func entry(for word: String) -> DictionaryEntry? {
        guard let dictionaries = activeDictionaries()?.takeUnretainedValue() as? [CFTypeRef] else { return nil }
        for dictionary in dictionaries {
            guard let records = copyRecords(dictionary, word as CFString, Self.exactMatch, 12)?.takeRetainedValue() as? [CFTypeRef] else { continue }
            for record in records {
                guard let title = headword(record)?.takeUnretainedValue() as String?,
                      title.compare(word, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
                      let text = copyRecordData(record, Self.plainTextVersion)?.takeRetainedValue() as? String
                else { continue }
                let name = dictionaryName(dictionary)?.takeUnretainedValue() as String? ?? "系统词典"
                if let entry = DictionaryTextParser.parse(text, query: word, dictionaryName: name) {
                    return entry
                }
            }
        }
        return nil
    }
}

/// 把词典的纯文本（"run | BrE rʌn, AmE rən | A. intransitive verb ① …"）整理成分行结构
nonisolated enum DictionaryTextParser {
    static func parse(_ raw: String, query: String, dictionaryName: String) -> DictionaryEntry? {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var headword = query
        var pronunciations: [DictionaryEntry.Pronunciation] = []

        let parts = body.components(separatedBy: " | ")
        if parts.count >= 2, parts[0].compare(query, options: .caseInsensitive) == .orderedSame {
            headword = parts[0]
            if parts.count >= 3 {
                pronunciations = parsePronunciations(parts[1])
                body = parts[2...].joined(separator: " | ")
            } else {
                body = parts[1]
            }
        } else if query.contains(" ") {
            // 短语动词（如 take off）嵌在主词条 take 里，截出对应的小节
            guard let section = phrasalSection(in: body, phrase: query) else { return nil }
            body = section
        } else {
            return nil
        }

        let lines = formatLines(body)
        guard !lines.isEmpty else { return nil }
        return DictionaryEntry(dictionaryName: dictionaryName, headword: headword, pronunciations: pronunciations, lines: lines)
    }

    /// "BrE ˈdeɪtə, ˈdɑːtə, AmE ˈdædə" → 英 /ˈdeɪtə, ˈdɑːtə/、美 /ˈdædə/
    private static func parsePronunciations(_ text: String) -> [DictionaryEntry.Pronunciation] {
        var groups: [(label: String, voice: String, ipa: [String])] = []
        for token in text.components(separatedBy: ", ") {
            if token.hasPrefix("BrE ") {
                groups.append(("英", "en-GB", [String(token.dropFirst(4))]))
            } else if token.hasPrefix("AmE ") {
                groups.append(("美", "en-US", [String(token.dropFirst(4))]))
            } else if !groups.isEmpty {
                groups[groups.count - 1].ipa.append(token)
            } else {
                groups.append(("", "en-US", [token]))
            }
        }
        return groups.map { .init(label: $0.label, ipa: $0.ipa.joined(separator: ", "), voiceLanguage: $0.voice) }
    }

    private static func phrasalSection(in text: String, phrase: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let start = text.range(of: "\(escaped) (?=A\\. |[\\x{2460}-\\x{2473}]|\\[)", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let first = NSRegularExpression.escapedPattern(for: String(phrase.prefix { $0 != " " }))
        // 到下一个同词根的短语小节为止
        let rest = text[start.upperBound...]
        let nextPattern = "\\b\(first) [a-z]+(?: [a-z]+)? (?=A\\. |[\\x{2460}-\\x{2473}])"
        let end = rest.range(of: nextPattern, options: [.regularExpression, .caseInsensitive])?.lowerBound ?? rest.endIndex
        let section = rest[..<end].trimmingCharacters(in: .whitespaces)
        return section.isEmpty ? nil : section
    }

    private static let circledNumbers = #"[\x{2460}-\x{2473}\x{3251}-\x{325F}\x{32B1}-\x{32BF}]"#

    private static func formatLines(_ body: String) -> [DictionaryEntry.Line] {
        var text = stripPinyin(body)
        // A. B. … 词性大段
        text = text.replacingOccurrences(of: #"(?:^|\s)([A-H])\. (?=[a-z\[])"#, with: "\n§$1. ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*\bPHRASAL VERBS?\b\s*"#, with: "\n§短语动词\n", options: .regularExpression)
        // ① ② … 义项
        text = text.replacingOccurrences(of: #"\s*(\#(circledNumbers))\s*"#, with: "\n$1 ", options: .regularExpression)
        // ▸ 例句
        text = text.replacingOccurrences(of: #"\s*▸\s*"#, with: "\n▸ ", options: .regularExpression)

        var lines: [DictionaryEntry.Line] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let kind: DictionaryEntry.Line.Kind
            if line.hasPrefix("§") {
                kind = .section
                line.removeFirst()
            } else if line.hasPrefix("▸") {
                kind = .example
                line = line.dropFirst().trimmingCharacters(in: .whitespaces)
            } else if line.range(of: "^\(circledNumbers)", options: .regularExpression) != nil {
                kind = .sense
            } else {
                kind = .plain
            }
            lines.append(.init(id: lines.count, kind: kind, text: line))
        }
        return lines
    }

    /// 去掉汉字后面附带的拼音（"跑步 pǎobù" → "跑步"），对中文用户是噪音
    private static func stripPinyin(_ text: String) -> String {
        let toned = "āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ"
        let syllable = "[a-zü'\(toned)]+"
        let pattern = "(?<=[\\p{Han}）)])\\s+(?=[a-zü]*[\(toned)])\(syllable)(?:\\s+\(syllable))*"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
