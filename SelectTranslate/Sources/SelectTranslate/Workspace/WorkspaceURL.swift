import Foundation

nonisolated enum WorkspaceURL {
    static func isSafeWebURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "https" && parts.host?.isEmpty == false
            && parts.user == nil && parts.password == nil
    }

    static func destination(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), isSafeWebURL(url) { return url }
        if let url = URL(string: text), url.scheme != nil { return nil }
        if !text.contains("://"), !text.contains(where: \.isWhitespace), text.contains("."),
           let url = URL(string: "https://" + text), isSafeWebURL(url) { return url }
        // 非网页协议和带凭据的网址不能当作搜索词发送出去。
        if text.contains("://") { return nil }
        var search = URLComponents(string: "https://www.bing.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}
