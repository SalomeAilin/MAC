import Testing
@testable import SelectTranslate

struct WorkspaceNetworkTests {
    @Test(arguments: [
        ("state=OK checked=2026-10-25T12:00:00Z checks=22 domain_routes=5", WorkspaceNetworkState.ok),
        ("state=FALLBACK checked=2026-10-25T12:00:00Z checks=22", .fallback),
        ("state=BAD checked=2026-10-25T12:00:00Z checks=22\nDNS: bad timeout", .bad),
        ("usage: network-domain-engine status", .unknown),
        ("", .unknown),
        ("state=NEW checked=2026-10-25T12:00:00Z", .unknown),
    ])
    func preservesFailuresAndUnknownResults(_ output: String, _ expected: WorkspaceNetworkState) {
        #expect(WorkspaceNetworkState(output: output) == expected)
    }
}
