import Foundation

/// 谷歌网页翻译使用的公开接口：免费、不需要 Key，但不是官方 API，可能随时变化
enum GoogleTranslator {
    private static let endpoint = URL(string: "https://translate.googleapis.com/translate_a/single")!

    static func translate(_ text: String, to target: Language) async throws -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: googleCode(for: target)),
            URLQueryItem(name: "dt", value: "t"),
        ]
        // 原文放在 POST 正文里，长文本也不会超出 URL 长度限制
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("q=\(formEncode(text))".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw TranslationFailure.message("连不上谷歌翻译，请检查网络（需要能访问谷歌）")
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationFailure.message("谷歌翻译返回了无效的响应")
        }
        switch http.statusCode {
        case 200: break
        case 429: throw TranslationFailure.message("谷歌翻译请求太频繁，请稍后再试")
        default: throw TranslationFailure.message("谷歌翻译请求失败（\(http.statusCode)）")
        }
        guard let translation = parse(data), !translation.isBlank else {
            throw TranslationFailure.message("谷歌翻译返回了无法识别的结果")
        }
        return translation
    }

    /// 返回值形如 [[["译文片段", "原文片段", …], …], null, "en", …]，按顺序拼接译文片段
    private static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any]
        else { return nil }
        return segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
    }

    private static func googleCode(for language: Language) -> String {
        switch language.code {
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        default: language.code
        }
    }

    /// 表单编码：只保留 ASCII 字母数字和 -._~，其余（包括中文）按 UTF-8 转义
    private static func formEncode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
