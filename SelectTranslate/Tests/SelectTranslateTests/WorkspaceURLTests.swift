import Foundation
import Testing
@testable import SelectTranslate

struct WorkspaceURLTests {
    @Test func acceptsHTTPSAndNormalizesBareDomains() {
        #expect(WorkspaceURL.destination(for: "https://example.com/page")?.absoluteString == "https://example.com/page")
        #expect(WorkspaceURL.destination(for: "example.com/page")?.absoluteString == "https://example.com/page")
    }

    @Test func searchesTextWithoutInterpretingItAsHTML() throws {
        let url = try #require(WorkspaceURL.destination(for: "学习 Swift 与手写笔记"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.scheme == "https")
        #expect(query?.first(where: { $0.name == "q" })?.value == "学习 Swift 与手写笔记")
    }

    @Test(arguments: ["file:///etc/hosts", "javascript:alert(1)", "data:text/html,test", "http://example.com", "https://user:password@example.com"])
    func rejectsUnsafeURLsInsteadOfSearchingThem(_ value: String) {
        #expect(WorkspaceURL.destination(for: value) == nil)
    }
}
