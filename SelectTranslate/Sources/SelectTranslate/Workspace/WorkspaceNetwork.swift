import Foundation
import Observation

nonisolated enum WorkspaceNetworkState: String {
    case ok = "OK", fallback = "FALLBACK", bad = "BAD", unknown

    init(output: String) {
        let token = output.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        self = token.hasPrefix("state=") ? (Self(rawValue: String(token.dropFirst(6))) ?? .unknown) : .unknown
    }
}

@Observable
final class WorkspaceNetwork {
    private(set) var output = "尚未检查"
    private(set) var checkedAt: Date?
    private(set) var isRunning = false
    private(set) var error: String?
    var state: WorkspaceNetworkState { WorkspaceNetworkState(output: output) }
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var cancelled = false

    func refresh() {
        guard !isRunning else { return }
        let executable = "/usr/local/libexec/network-domain-engine"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            error = "未找到已安装的网络分流引擎。请先按网络项目的安装流程配置。"
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        // 对外 status 命令内部使用只读检查，不发布状态页或写回执。
        process.arguments = ["status"]
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            self.error = error.localizedDescription
            return
        }
        self.process = process
        cancelled = false
        isRunning = true
        error = nil
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(95)) } catch { return }
            guard self?.process === process, process.isRunning else { return }
            self?.error = "本次检查超时，已取消。"
            process.terminate()
        }
        Task { [weak self] in
            let result = await Task.detached {
                var data = Data()
                do {
                    while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                        if data.count < 128 * 1024 { data.append(chunk.prefix(128 * 1024 - data.count)) }
                    }
                } catch { /* 退出时仍显示已经取得的有限输出。 */ }
                process.waitUntilExit()
                return (String(decoding: data, as: UTF8.self), process.terminationStatus)
            }.value
            guard let self, self.process === process else { return }
            self.timeout?.cancel()
            self.timeout = nil
            self.process = nil
            self.isRunning = false
            guard !self.cancelled else { return }
            self.output = result.0.isEmpty ? "没有收到状态结果" : result.0
            self.checkedAt = Date()
            if result.1 != 0, self.error == nil { self.error = "检查未正常完成，请查看结果中的原因。" }
        }
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        if let process, process.isRunning {
            cancelled = true
            error = "已取消本次检查。"
            process.terminate()
        }
    }
}
