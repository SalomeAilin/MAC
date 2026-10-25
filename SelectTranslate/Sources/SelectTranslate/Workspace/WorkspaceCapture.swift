import AppKit
import Observation
import Vision

@Observable
final class WorkspaceCapture {
    private(set) var isCapturing = false
    private(set) var isRecognizing = false
    private(set) var error: String?
    var recognizedText = ""
    var isPreviewingText = false
    private(set) var recognizedNoteID: UUID?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?

    func capture(into notes: WorkspaceNotes, hide: @escaping () -> Void, restore: @escaping () -> Void) {
        guard !isCapturing, !notes.isReadOnly else { return }
        isCapturing = true
        error = nil
        hide()
        captureTask = Task { [weak self] in
            guard let self else { return }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("selecttranslate-capture-\(UUID().uuidString)", isDirectory: true)
            defer {
                // 这里只清理本次截图的暂存目录，已保存到笔记的附件保留。
                try? FileManager.default.removeItem(at: temporary)
                self.process = nil
                self.isCapturing = false
                restore()
            }
            do {
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let imageURL = temporary.appendingPathComponent("selection.png")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", "-t", "png", imageURL.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                self.process = process
                let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                    do { try process.run() } catch { continuation.resume(throwing: error) }
                }
                guard !Task.isCancelled, status == 0, FileManager.default.fileExists(atPath: imageURL.path) else { return }
                let values = try imageURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size > 0, size <= 32 * 1024 * 1024,
                      NSImage(contentsOf: imageURL) != nil
                else { throw WorkspaceStorageError.invalidDocument }
                try notes.repository.prepareAttachments()
                let attachment = WorkspaceAttachment(id: UUID())
                let destination = notes.repository.attachmentsURL.appendingPathComponent(attachment.filename)
                try FileManager.default.copyItem(at: imageURL, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                if notes.add(title: "截图 \(Date().formatted(date: .numeric, time: .shortened))", attachment: attachment) != nil {
                    if !notes.flush() { self.error = notes.error }
                } else {
                    try FileManager.default.removeItem(at: destination)
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func recognize(_ attachment: WorkspaceAttachment, noteID: UUID, in notes: WorkspaceNotes) {
        guard !isRecognizing else { return }
        let url = notes.repository.attachmentsURL.appendingPathComponent(attachment.filename)
        isRecognizing = true
        error = nil
        recognitionTask = Task { [weak self] in
            defer { self?.isRecognizing = false }
            do {
                let text = try await Task.detached {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                    request.automaticallyDetectsLanguage = true
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(url: url).perform([request])
                    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                }.value
                guard !Task.isCancelled, let self else { return }
                if text.isBlank { self.error = "没有识别到文字，可以尝试截取更清晰的区域。" }
                else {
                    self.recognizedText = text
                    self.recognizedNoteID = noteID
                    self.isPreviewingText = true
                }
            } catch { self?.error = error.localizedDescription }
        }
    }

    func cancel() {
        captureTask?.cancel()
        recognitionTask?.cancel()
        if let process, process.isRunning { process.terminate() }
    }
}
