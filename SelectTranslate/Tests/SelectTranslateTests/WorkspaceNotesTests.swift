import Foundation
import Testing
@testable import SelectTranslate

@MainActor
struct WorkspaceNotesTests {
    private func withRepository(_ body: (WorkspaceNotesRepository) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("selecttranslate-notes-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(WorkspaceNotesRepository(directory: directory))
    }

    @Test func savesUnicodeSourcesAndScreenshotReferencesAcrossReopen() throws {
        try withRepository { repository in
            let notes = WorkspaceNotes(repository: repository)
            let attachment = WorkspaceAttachment(id: UUID())
            let id = notes.add(title: "今天的记录", body: "你好，世界。\nHello!", source: URL(string: "https://example.com/article"), attachment: attachment)
            #expect(id != nil)
            #expect(notes.flush())
            let reopened = try WorkspaceNotesRepository(directory: repository.directory).load()
            #expect(reopened.notes.count == 1)
            #expect(reopened.notes.first?.body == "你好，世界。\nHello!")
            #expect(reopened.notes.first?.attachments == [attachment])
            #expect(reopened.notes.first?.sourceURL?.host == "example.com")
            let permissions = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)
        }
    }

    @Test func corruptedDataStaysUntouchedAndReadOnly() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let original = Data("not a valid document".utf8)
            try original.write(to: repository.fileURL)
            let notes = WorkspaceNotes(repository: repository)
            #expect(notes.isReadOnly)
            #expect(notes.add(title: "不应写入") == nil)
            #expect(try Data(contentsOf: repository.fileURL) == original)
        }
    }

    @Test func externalChangesDoNotGetOverwritten() throws {
        try withRepository { repository in
            let notes = WorkspaceNotes(repository: repository)
            let id = try #require(notes.add(title: "原文", body: "原内容"))
            #expect(notes.flush())
            let externallyChanged = WorkspaceDocument(notes: [WorkspaceNote(title: "外部修改", body: "必须保留")])
            let externalData = try JSONEncoder().encode(externallyChanged)
            try externalData.write(to: repository.fileURL)
            notes.update(id: id, body: "尚未保存的编辑")
            #expect(!notes.flush())
            #expect(notes.hasUnsavedChanges)
            #expect(notes.selectedNote?.body == "尚未保存的编辑")
            #expect(try Data(contentsOf: repository.fileURL) == externalData)
        }
    }

    @Test func duplicateIDsCannotReplaceValidData() throws {
        try withRepository { repository in
            _ = try repository.load()
            let note = WorkspaceNote(title: "保留", body: "正文")
            try repository.save(WorkspaceDocument(notes: [note]))
            let before = try Data(contentsOf: repository.fileURL)
            #expect(throws: (any Error).self) {
                try repository.save(WorkspaceDocument(notes: [note, note]))
            }
            #expect(try Data(contentsOf: repository.fileURL) == before)
        }
    }

    @Test func dailyEntryReusesTheSameNote() throws {
        try withRepository { repository in
            let notes = WorkspaceNotes(repository: repository)
            notes.openToday()
            let firstID = notes.selectedID
            notes.openToday()
            #expect(notes.selectedID == firstID)
            #expect(notes.document.notes.count == 1)
            #expect(notes.selectedNote?.diaryDay != nil)
            #expect(notes.flush())
        }
    }

    @Test func symlinkCannotRedirectWritesToAnotherFile() throws {
        try withRepository { repository in
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            let original = repository.directory.appendingPathComponent("keep.json")
            let bytes = Data("private original".utf8)
            try bytes.write(to: original)
            try FileManager.default.createSymbolicLink(at: repository.fileURL, withDestinationURL: original)
            let notes = WorkspaceNotes(repository: repository)
            #expect(notes.isReadOnly)
            #expect(try Data(contentsOf: original) == bytes)
        }
    }
}
