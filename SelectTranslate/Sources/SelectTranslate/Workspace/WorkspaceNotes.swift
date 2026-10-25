import Foundation
import Observation

nonisolated struct WorkspaceAttachment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var filename: String { "\(id.uuidString).png" }
}

nonisolated struct WorkspaceNote: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var body: String
    var createdAt = Date()
    var updatedAt = Date()
    var diaryDay: String?
    var sourceURL: URL?
    var attachments: [WorkspaceAttachment] = []
}

nonisolated struct WorkspaceDocument: Codable, Equatable, Sendable {
    var version = 1
    var notes: [WorkspaceNote] = []

    func validated() throws -> Self {
        guard version == 1, notes.count <= 10_000, Set(notes.map(\.id)).count == notes.count,
              notes.allSatisfy({ note in
                  note.title.utf8.count <= 4096 && note.body.utf8.count <= 4 * 1024 * 1024
                      && note.createdAt.timeIntervalSince1970.isFinite && note.updatedAt.timeIntervalSince1970.isFinite
                      && note.attachments.count <= 100
                      && Set(note.attachments.map(\.id)).count == note.attachments.count
                      && (note.sourceURL == nil || WorkspaceURL.isSafeWebURL(note.sourceURL!))
              })
        else { throw WorkspaceStorageError.invalidDocument }
        return self
    }
}

enum WorkspaceStorageError: LocalizedError {
    case invalidDocument, changedOnDisk, unsafeLocation

    var errorDescription: String? {
        switch self {
        case .invalidDocument: "无法确认笔记文件的内容，已停止保存并保留原文件。"
        case .changedOnDisk: "笔记文件已被其他程序修改，已停止保存。当前编辑仍保留在窗口中，请先导出。"
        case .unsafeLocation: "笔记目录或文件不是普通文件，已停止写入。"
        }
    }
}

/// Mac 文字笔记使用独立目录，不读取或改写 iPad 手写资料库。
final class WorkspaceNotesRepository {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("notes.json") }
    var attachmentsURL: URL { directory.appendingPathComponent("Attachments", isDirectory: true) }
    private var lastReadData: Data?

    init(directory: URL) { self.directory = directory }

    func load() throws -> WorkspaceDocument {
        try rejectSymlink(directory)
        try rejectSymlink(fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return WorkspaceDocument() }
        let data = try boundedData(fileURL)
        let document = try JSONDecoder().decode(WorkspaceDocument.self, from: data).validated()
        lastReadData = data
        return document
    }

    func save(_ document: WorkspaceDocument) throws {
        let data = try JSONEncoder().encode(document.validated())
        guard data.count <= 64 * 1024 * 1024 else { throw WorkspaceStorageError.invalidDocument }
        try prepareDirectory(directory)
        try rejectSymlink(fileURL)
        let current = FileManager.default.fileExists(atPath: fileURL.path) ? try boundedData(fileURL) : nil
        guard current == lastReadData else { throw WorkspaceStorageError.changedOnDisk }
        try data.write(to: fileURL, options: .atomic)
        lastReadData = data
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func prepareAttachments() throws {
        try prepareDirectory(directory)
        try prepareDirectory(attachmentsURL)
    }

    private func boundedData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 64 * 1024 * 1024 else {
            throw WorkspaceStorageError.invalidDocument
        }
        return try Data(contentsOf: url)
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw WorkspaceStorageError.unsafeLocation
        }
    }

    private func prepareDirectory(_ url: URL) throws {
        try rejectSymlink(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

@Observable
final class WorkspaceNotes {
    private(set) var document = WorkspaceDocument()
    var selectedID: UUID?
    private(set) var error: String?
    private(set) var isReadOnly = false
    private(set) var hasUnsavedChanges = false
    let repository: WorkspaceNotesRepository
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var selectedNote: WorkspaceNote? { document.notes.first { $0.id == selectedID } }
    var sortedNotes: [WorkspaceNote] { document.notes.sorted { $0.updatedAt > $1.updatedAt } }

    init(repository: WorkspaceNotesRepository) {
        self.repository = repository
        do {
            document = try repository.load()
            selectedID = sortedNotes.first?.id
        } catch {
            isReadOnly = true
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(title: String = "新笔记", body: String = "", source: URL? = nil, attachment: WorkspaceAttachment? = nil) -> UUID? {
        guard !isReadOnly else { return nil }
        var note = WorkspaceNote(title: title, body: body, sourceURL: source)
        if let attachment { note.attachments.append(attachment) }
        document.notes.append(note)
        selectedID = note.id
        changed()
        return note.id
    }

    func openToday() {
        guard !isReadOnly else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())
        if let note = document.notes.first(where: { $0.diaryDay == day }) {
            selectedID = note.id
        } else if let id = add(title: "\(day) 日记"), let index = document.notes.firstIndex(where: { $0.id == id }) {
            document.notes[index].diaryDay = day
        }
    }

    func update(id: UUID, title: String? = nil, body: String? = nil) {
        guard !isReadOnly, let index = document.notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { document.notes[index].title = title }
        if let body { document.notes[index].body = body }
        document.notes[index].updatedAt = Date()
        changed()
    }

    @discardableResult
    func flush() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return true }
        guard !isReadOnly else { return false }
        do {
            try repository.save(document)
            hasUnsavedChanges = false
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func changed() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.flush()
        }
    }
}
