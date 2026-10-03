import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 通过辅助功能 API 读到的选区状态
nonisolated enum AXSelection: Sendable {
    case text(String)
    case empty        // 焦点控件支持选区，但当前没有选中内容
    case unsupported  // 无法读取（如 Chrome、Electron 应用）
}

/// 读取当前前台 App 中选中的文字
enum SelectionReader {
    private static var clipboardReadInProgress = false
    private static let copyEventMarker: Int64 = 0x535452414E534C

    /// 优先用辅助功能 API；读不到时模拟 ⌘C，从同一前台 App 读取。
    static func read(processID: pid_t?, allowClipboardFallback: Bool) async -> String? {
        guard let processID, isFrontmost(processID), !Task.isCancelled else { return nil }
        if case .text(let text) = await readViaAccessibility(processID: processID) {
            return !Task.isCancelled && isFrontmost(processID) ? text : nil
        }
        // 有些 App（如 VS Code）的 AX 选区永远是空的，同样需要走剪贴板
        guard allowClipboardFallback, !Task.isCancelled else { return nil }
        let text = await readViaClipboard(processID: processID)
        selectionLog.notice("clipboard fallback: \(text.map { "\($0.count) chars" } ?? "nothing copied", privacy: .public)")
        return text
    }

    /// processID 是前台 App 的进程号；直接问该 App 比问系统全局焦点更可靠
    nonisolated static func readViaAccessibility(processID: pid_t?) async -> AXSelection {
        let systemWide = AXUIElementCreateSystemWide()
        // 全局超时：防止目标 App 卡住时长时间阻塞
        AXUIElementSetMessagingTimeout(systemWide, 0.35)

        var focusedRef: CFTypeRef?
        // 已指定来源时不回退到另一个 App 的全局焦点。
        let target = processID.map { AXUIElementCreateApplication($0) } ?? systemWide
        let focusStatus = AXUIElementCopyAttributeValue(target, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusStatus == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            selectionLog.notice("AX: no focused element (error \(focusStatus.rawValue, privacy: .public))")
            return .unsupported
        }
        let focused = focusedRef as! AXUIElement
        let role = stringAttribute(kAXRoleAttribute, of: focused) ?? "?"

        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &valueRef)
        if status == .success, let text = valueRef as? String, !text.isBlank {
            selectionLog.notice("AX: \(role, privacy: .public) selected text, \(text.count) chars")
            return .text(text)
        }

        // 网页内容（Safari、Chromium）用 TextMarker 表示选区；焦点可能在网页里的子元素上，向上找网页区域
        for element in [focused] + ancestors(of: focused, withRole: "AXWebArea") {
            if let text = selectedTextViaMarkers(element) {
                selectionLog.notice("AX: \(role, privacy: .public) text marker selection, \(text.count) chars")
                return .text(text)
            }
        }
        selectionLog.notice("AX: \(role, privacy: .public) has no readable selection (AXSelectedText error \(status.rawValue, privacy: .public))")
        return status == .success ? .empty : .unsupported
    }

    private nonisolated static func selectedTextViaMarkers(_ element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &rangeRef) == .success,
              let rangeRef
        else { return nil }
        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, rangeRef, &stringRef) == .success,
              let text = stringRef as? String, !text.isBlank
        else { return nil }
        return text
    }

    /// 向上查找指定角色的祖先元素（最多 12 层）
    private nonisolated static func ancestors(of element: AXUIElement, withRole role: String) -> [AXUIElement] {
        var current = element
        for _ in 0..<12 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef, CFGetTypeID(parentRef) == AXUIElementGetTypeID()
            else { return [] }
            let parent = parentRef as! AXUIElement
            if stringAttribute(kAXRoleAttribute, of: parent) == role { return [parent] }
            current = parent
        }
        return []
    }

    private nonisolated static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else { return nil }
        return valueRef as? String
    }

    /// 同时只发出一次模拟复制。发生用户输入、切换 App 或其他写入时保留新剪贴板。
    static func readViaClipboard(processID: pid_t) async -> String? {
        while clipboardReadInProgress {
            guard !Task.isCancelled, isFrontmost(processID) else { return nil }
            do { try await Task.sleep(for: .milliseconds(15)) } catch { return nil }
        }
        guard !Task.isCancelled, isFrontmost(processID) else { return nil }
        clipboardReadInProgress = true
        defer { clipboardReadInProgress = false }

        let interruption = ClipboardReadInterruption()
        interruption.start()
        defer { interruption.stop() }
        let canContinue = { !interruption.interrupted && isFrontmost(processID) }
        guard await waitForModifierKeysRelease(canContinue: canContinue), !Task.isCancelled, canContinue() else { return nil }

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let snapshot = PasteboardSnapshot(pasteboard)
        guard pasteboard.changeCount == initialChangeCount, !Task.isCancelled, canContinue() else { return nil }
        var copiedChangeCount: Int?
        defer {
            // NSPasteboard 没有跨进程事务；仅在仍是本次观察到的版本且没有用户操作时恢复。
            if let copiedChangeCount, !Task.isCancelled, canContinue(), pasteboard.changeCount == copiedChangeCount {
                snapshot.restore(to: pasteboard)
            }
        }

        guard postCopyShortcut(processID: processID) else { return nil }

        let deadline = ContinuousClock.now + .milliseconds(600)
        while pasteboard.changeCount == initialChangeCount, ContinuousClock.now < deadline {
            guard !Task.isCancelled, canContinue() else { return nil }
            do { try await Task.sleep(for: .milliseconds(15)) } catch { return nil }
        }
        guard !Task.isCancelled, canContinue(), pasteboard.changeCount != initialChangeCount else { return nil }
        let observedChangeCount = pasteboard.changeCount
        copiedChangeCount = observedChangeCount

        // 有的 App 先清空再分步写入，稍等一下再读
        var text = pasteboard.string(forType: .string)
        if text == nil {
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return nil }
            // 无法确认后续写入归属时，不覆盖剪贴板，也不使用可能已经变化的选区。
            guard !Task.isCancelled, canContinue(), pasteboard.changeCount == observedChangeCount else { return nil }
            text = pasteboard.string(forType: .string)
        }
        guard !Task.isCancelled, canContinue(), pasteboard.changeCount == observedChangeCount else { return nil }
        guard let text, !text.isBlank else { return nil }
        return text
    }

    /// 快捷键触发时用户往往还按着 ⌥，等修饰键松开再发 ⌘C
    private static func waitForModifierKeysRelease(canContinue: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(400)
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, canContinue() else { return false }
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { return true }
            do { try await Task.sleep(for: .milliseconds(15)) } catch { return false }
        }
        return false
    }

    static func isOwnCopyEvent(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == copyEventMarker
    }

    private static func isFrontmost(_ processID: pid_t) -> Bool {
        processID != ProcessInfo.processInfo.processIdentifier
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
    }

    private static func postCopyShortcut(processID: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: copyEventMarker)
            event.postToPid(processID)
        }
        return true
    }
}

/// 只在剪贴板事务期间监听输入，避免把用户的复制误认成本次模拟复制。
private final class ClipboardReadInterruption {
    private(set) var interrupted = false
    private var monitors: [Any] = []

    func start() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if !SelectionReader.isOwnCopyEvent(event) { self?.interrupted = true }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if !SelectionReader.isOwnCopyEvent(event) { self?.interrupted = true }
            return event
        }) { monitors.append(monitor) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// 保存可读取的各类型数据，仅在剪贴板版本仍归属本次读取时恢复。
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

extension String {
    nonisolated var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
