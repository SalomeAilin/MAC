import AppKit
import Carbon.HIToolbox

/// 监听全局鼠标：拖选、双击、三击、Shift 点击之后检查是否选中了文字
final class SelectionMonitor {
    /// 选中了文字。text 为 nil 表示该 App 读不到 AX 选区，需要用 ⌘C 读取
    var onSelection: ((String?, NSPoint, pid_t) -> Void)?
    /// 打字、滚动、再次点击等操作发生，划词图标应当隐藏
    var onInterruption: (() -> Void)?

    private var monitors: [Any] = []
    private var mouseDownLocation: NSPoint = .zero
    private var mouseDownWindow: WindowSnapshot?
    private var pendingCheck: Task<Void, Never>?
    private var pendingHover: SelectionHover?
    private var hoverTask: Task<Void, Never>?
    private var hoverSource: NSRunningApplication?
    private var dismissedHover: DismissedHover?

    func start() {
        guard monitors.isEmpty else { return }
        add(.leftMouseDown) { [weak self] _ in self?.mouseDown() }
        add(.leftMouseUp) { [weak self] event in self?.mouseUp(event) }
        add(.mouseMoved) { [weak self] _ in
            self?.updateHover()
        }
        add([.keyDown, .scrollWheel, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.interrupt(event)
        }
        // 自己的窗口不会收到全局监视器事件，也要撤销尚未完成的读取。
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel], handler: { [weak self] event in
            if event.type == .mouseMoved {
                self?.updateHover()
                return event
            }
            // 划词图标使用 popUpMenu 层级，必须保留它自己的点击以完成翻译。
            if event.type == .leftMouseDown, event.window?.level == .popUpMenu { return event }
            self?.interrupt(event)
            return event
        }) {
            monitors.append(monitor)
        }
        selectionLog.notice("selection monitor started (\(self.monitors.count, privacy: .public) monitors)")
    }

    func stop() {
        guard !monitors.isEmpty else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
        selectionLog.notice("selection monitor stopped")
    }

    private func add(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    private func mouseDown() {
        cancelPendingCheck()
        onInterruption?()
        mouseDownLocation = NSEvent.mouseLocation
        mouseDownWindow = WindowSnapshot.under(mouseDownLocation)
    }

    func reset() {
        cancelPendingCheck()
        dismissedHover = nil
    }

    private func cancelPendingCheck() {
        pendingCheck?.cancel()
        pendingCheck = nil
        pendingHover = nil
        hoverTask?.cancel()
        hoverTask = nil
        hoverSource = nil
    }

    func waitingBounds(processID: pid_t, at point: CGPoint) -> [CGRect]? {
        guard hoverSource?.processIdentifier == processID, let hover = pendingHover,
              hover.isWaiting(at: point) else { return nil }
        return hover.bounds
    }

    func escapeFeedback(processID: pid_t) -> (() -> Void)? {
        guard hoverSource?.processIdentifier == processID, let bounds = pendingHover?.bounds,
              let windowID = mouseDownWindow?.number else { return nil }
        let shownAt = ContinuousClock.now
        return { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
                  AppSettings.shared.selectionAction == .translate else { return }
            self?.dismissedHover = DismissedHover(processID: processID, windowID: windowID, bounds: bounds,
                                                  shownAt: shownAt, escapedAt: .now)
        }
    }

    private func checkExtension(_ bounds: [CGRect], processID: pid_t, windowID: CGWindowID?) {
        guard let dismissedHover else { return }
        self.dismissedHover = nil
        if dismissedHover.wasExtended(to: bounds, processID: processID, windowID: windowID, at: .now) {
            AppSettings.shared.recordHoverFeedback(.extendedAfterEscape)
        }
    }

    private func interrupt(_ event: NSEvent) {
        guard !SelectionReader.isOwnCopyEvent(event), !HotkeyCenter.shared.isSelectionShortcut(event) else { return }
        cancelPendingCheck()
        onInterruption?()
        // 面板自己的 Esc 监听器和全局监听器的回调顺序不固定。
        if event.type == .keyDown, Int(event.keyCode) == kVK_Escape { return }
        guard let dismissal = dismissedHover else { return }
        let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        guard event.type == .keyDown, event.modifierFlags.contains(.shift), arrows.contains(Int(event.keyCode)),
              ContinuousClock.now - dismissal.escapedAt <= DismissedHover.extensionWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == dismissal.processID
        else { dismissedHover = nil; return }
        let windowID = WindowSnapshot.under(NSEvent.mouseLocation)?.number
        pendingCheck = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(45)) } catch { return }
            let bounds = await SelectionReader.selectionBounds(processID: dismissal.processID)
            guard !Task.isCancelled else { return }
            self?.checkExtension(bounds, processID: dismissal.processID, windowID: windowID)
        }
    }

    /// 供剪贴板读取完成后复查，避免读取期间移出选区仍然弹出译文。
    func hasCompletedHover(processID: pid_t) -> Bool {
        guard hoverSource?.processIdentifier == processID else { return false }
        return pendingHover?.update(at: NSEvent.mouseLocation) == true
    }

    private func updateHover() {
        guard let delay = pendingHover?.delay, let source = hoverSource else { return }
        _ = pendingHover?.update(at: NSEvent.mouseLocation)
        guard pendingHover?.isInside == true else {
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        guard hoverTask == nil else { return }
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self,
                  self.hasCompletedHover(processID: source.processIdentifier)
            else { return }
            await self.readSelection(in: source, at: NSEvent.mouseLocation, requiresHover: true)
        }
    }

    private func mouseUp(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        let dragged = distance >= 5
        let multiClick = event.clickCount >= 2
        let shiftClick = event.modifierFlags.contains(.shift)
        guard dragged || multiClick || shiftClick else { dismissedHover = nil; return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let appID = app.bundleIdentifier ?? app.localizedName ?? "?"
        selectionLog.notice("mouse up in \(appID, privacy: .public): drag \(Int(distance), privacy: .public)pt, clicks \(event.clickCount, privacy: .public)")

        // 拖动或缩放窗口时窗口位置会变，不是在选字
        if dragged, let before = mouseDownWindow, let now = before.currentBounds(), now != before.bounds {
            dismissedHover = nil
            selectionLog.notice("skip: window moved or resized")
            return
        }

        let processID = app.processIdentifier
        pendingCheck = Task { [weak self] in
            // 给目标 App 一点时间更新选区
            try? await Task.sleep(for: .milliseconds(multiClick ? 90 : 40))
            guard !Task.isCancelled else { return }
            // 图标模式保留原来的显示方式，自动翻译必须先确认光标停在选区上。
            if AppSettings.shared.selectionAction == .translate {
                let bounds = await SelectionReader.selectionBounds(processID: processID)
                guard !Task.isCancelled, let self else { return }
                self.checkExtension(bounds, processID: processID, windowID: self.mouseDownWindow?.number)
                guard !bounds.isEmpty else { return }
                self.pendingHover = SelectionHover(bounds: bounds, delay: AppSettings.shared.hoverTiming.delay)
                self.hoverSource = app
                self.updateHover()
                return
            }
            await self?.readSelection(in: app, at: location, requiresHover: false)
        }
    }

    private func readSelection(in app: NSRunningApplication, at location: NSPoint, requiresHover: Bool) async {
        let processID = app.processIdentifier
        let selection = await SelectionReader.readViaAccessibility(processID: processID)
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
        else { return }
        if requiresHover {
            let bounds = await SelectionReader.selectionBounds(processID: processID)
            guard !Task.isCancelled, AppSettings.shared.selectionAction == .translate,
                  hasCompletedHover(processID: processID),
                  bounds.contains(where: { $0.contains(NSEvent.mouseLocation) })
            else { return }
        }
        switch selection {
        case .text(let text):
            onSelection?(text, location, processID)
        case .empty, .unsupported:
            if AppTraits.needsClipboardFallback(app) {
                selectionLog.notice("selection needs clipboard fallback")
                onSelection?(nil, location, processID)
            }
        }
    }
}

/// 鼠标按下时所在窗口的位置，用来区分"选字"和"拖动窗口"
private struct WindowSnapshot {
    let number: CGWindowID
    let bounds: CGRect

    static func under(_ point: NSPoint) -> WindowSnapshot? {
        // CGWindow 坐标原点在主屏左上角
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = bounds(of: info), bounds.contains(cgPoint),
                  let number = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            return WindowSnapshot(number: number, bounds: bounds)
        }
        return nil
    }

    func currentBounds() -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]])?.first else { return nil }
        return Self.bounds(of: info)
    }

    private static func bounds(of info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}

/// 识别读不到 AX 选区、需要模拟 ⌘C 的 App（Chromium 内核浏览器和 Electron 应用）
enum AppTraits {
    private static var cache: [String: Bool] = [:]

    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium",
    ]

    static func needsClipboardFallback(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        if let cached = cache[bundleID] { return cached }
        var result = chromiumBrowsers.contains(bundleID)
        if !result, let bundleURL = app.bundleURL {
            let frameworks = bundleURL.appending(path: "Contents/Frameworks")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
            result = names.contains { $0.hasPrefix("Electron Framework") || $0.hasPrefix("Chromium Embedded Framework") }
                // 有的 Electron 应用改了框架名（如 Codex 的 "Codex Framework"），但都带 app.asar
                || FileManager.default.fileExists(atPath: bundleURL.appending(path: "Contents/Resources/app.asar").path)
        }
        cache[bundleID] = result
        return result
    }
}
