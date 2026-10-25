import Observation
import WebKit

@Observable
final class WorkspaceBrowser: NSObject, WKNavigationDelegate {
    var address = ""
    private(set) var error: String?
    private(set) var excerpt = ""
    private(set) var excerptTitle = ""
    private(set) var excerptURL: URL?
    var isPreviewing = false
    @ObservationIgnored let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open() {
        guard let url = WorkspaceURL.destination(for: address) else {
            error = "请输入 HTTPS 网址或搜索内容；不支持带账号密码的网址。"
            return
        }
        error = nil
        webView.load(URLRequest(url: url))
    }

    func previewSelection() {
        guard let url = webView.url, WorkspaceURL.isSafeWebURL(url) else { return }
        let title = webView.title ?? "网页摘录"
        Task {
            do {
                let value = try await webView.evaluateJavaScript("window.getSelection()?.toString() || ''")
                guard webView.url == url else { return }
                guard let text = value as? String, !text.isBlank else {
                    error = "请先在网页中选中要保存的文字。"
                    return
                }
                guard text.utf8.count <= 16 * 1024 else {
                    error = "选中的内容较多，请缩小范围后再保存。"
                    return
                }
                excerpt = text
                excerptTitle = title
                excerptURL = url
                error = nil
                isPreviewing = true
            } catch { self.error = error.localizedDescription }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.request.url?.absoluteString == "about:blank" { return .allow }
        guard let url = action.request.url, WorkspaceURL.isSafeWebURL(url) else {
            return .cancel
        }
        if action.targetFrame == nil {
            webView.load(URLRequest(url: url))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }

    func closeSession() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        address = ""
        excerpt = ""
        excerptTitle = ""
        excerptURL = nil
        isPreviewing = false
        webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}
