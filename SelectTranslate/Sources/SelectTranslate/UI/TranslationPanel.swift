import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 不激活 App 的浮动面板：弹出时原来的 App 仍在前台
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: TranslationView.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    // 无边框窗口默认不能成为 key window，需要接收键盘输入
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 未激活的窗口里第一次点击也要直接生效
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TranslationPanelController {
    let model = TranslationViewModel()
    var onOpenSettings: (() -> Void)?

    /// 面板以哪个点为锚：下方弹出时固定左上角，上方弹出时固定左下角
    private enum Anchor {
        case topLeft(NSPoint)
        case bottomLeft(NSPoint)
    }

    private var panel: FloatingPanel?
    private var anchor: Anchor = .topLeft(.zero)
    private var contentHeight: CGFloat = 160
    private var isApplyingLayout = false
    private var outsideClickMonitor: Any?
    private var passiveKeyMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    /// 显示并翻译。面板已固定时保持原位置（包括被 hideTemporarily 临时隐藏的情况）。
    /// passive：划词自动弹出时不抢键盘焦点，原 App 里可以照常复制、继续打字
    func show(text: String, near point: NSPoint, notice: String? = nil, passive: Bool = false) {
        let keepPosition = panel != nil && model.isPinned
        model.load(text: text, notice: notice)
        present(near: keepPosition ? nil : point, focusInput: text.isBlank && !passive, passive: passive)
    }

    /// 临时隐藏，让键盘焦点回到原来的 App（重新读取选区之前用）
    func hideTemporarily() {
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    func close() {
        panel?.orderOut(nil)
        model.cancel()
        model.isPinned = false
        Speaker.shared.stop()
        removeEventMonitors()
    }

    private func present(near point: NSPoint?, focusInput: Bool, passive: Bool) {
        let panel = self.panel ?? makePanel()
        if let point { anchor = anchor(near: point) }
        applyLayout()
        if passive {
            panel.orderFrontRegardless()
            installPassiveKeyMonitor()
        } else {
            removePassiveKeyMonitor()
            panel.makeKeyAndOrderFront(nil)
        }
        if focusInput {
            model.requestFocus()
        } else {
            // 成为 key window 时输入框会自动获得焦点并全选，划词翻译时不需要
            panel.makeFirstResponder(nil)
        }
        installOutsideClickMonitor()
    }

    /// 默认出现在鼠标右下方；下方空间不够时出现在上方
    private func anchor(near point: NSPoint) -> Anchor {
        let visible = screen(containing: point).visibleFrame
        let expectedHeight = max(contentHeight, 180)
        let x = point.x - 20
        if point.y - 18 - expectedHeight < visible.minY, point.y + 18 + expectedHeight < visible.maxY {
            return .bottomLeft(NSPoint(x: x, y: point.y + 18))
        }
        return .topLeft(NSPoint(x: x, y: point.y - 18))
    }

    private func applyLayout() {
        guard let panel else { return }
        let reference: NSPoint
        switch anchor {
        case .topLeft(let point), .bottomLeft(let point): reference = point
        }
        let visible = screen(containing: reference).visibleFrame
        let width = TranslationView.width
        let height = min(contentHeight, max(visible.height * 0.8, 240))

        var origin: NSPoint
        switch anchor {
        case .topLeft(let point): origin = NSPoint(x: point.x, y: point.y - height)
        case .bottomLeft(let point): origin = point
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - height - 8)

        isApplyingLayout = true
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        panel.invalidateShadow()
        isApplyingLayout = false
    }

    private func contentHeightChanged(_ height: CGFloat) {
        let height = ceil(height)
        guard abs(height - contentHeight) >= 1 else { return }
        contentHeight = height
        // 避免在 SwiftUI 布局过程中同步改窗口大小
        Task { @MainActor in
            if self.isVisible { self.applyLayout() }
        }
    }

    /// 用户拖动后以新的左上角为准
    private func panelDidMove() {
        guard !isApplyingLayout, let frame = panel?.frame else { return }
        anchor = .topLeft(NSPoint(x: frame.minX, y: frame.maxY))
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel()
        let actions = TranslationPanelActions(
            close: { [weak self] in self?.close() },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            downloadLanguages: { [weak self] source, target in
                LanguagePackDownloader.shared.present(source: source, target: target) {
                    self?.model.translate()
                }
            },
            contentHeightChanged: { [weak self] height in self?.contentHeightChanged(height) }
        )
        let hostingView = FirstMouseHostingView(rootView: TranslationView(model: model, actions: actions))
        hostingView.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = hostingView
        panel.contentView = glass

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidMove() }
        }
        self.panel = panel
        return panel
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // 只会收到其他 App 的点击；点自己的面板不受影响
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, !self.model.isPinned else { return }
            self.close()
        }
    }

    /// 面板没有键盘焦点时按键会发给原 App：按 Esc 或继续打字就关闭面板，⌘ 快捷键（如 ⌘C）不受影响
    private func installPassiveKeyMonitor() {
        guard passiveKeyMonitor == nil else { return }
        passiveKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !SelectionReader.isOwnCopyEvent(event) else { return }
            if Int(event.keyCode) == kVK_Escape || (!self.model.isPinned && !event.modifierFlags.contains(.command)) {
                self.close()
            }
        }
    }

    private func removePassiveKeyMonitor() {
        if let passiveKeyMonitor { NSEvent.removeMonitor(passiveKeyMonitor) }
        passiveKeyMonitor = nil
    }

    private func removeEventMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        removePassiveKeyMonitor()
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    #if DEBUG
    func debugSnapshot(to path: String) {
        panel?.contentView?.debugSnapshot(to: path)
    }
    #endif
}

#if DEBUG
extension NSView {
    /// 调试用：把视图渲染成 PNG（不需要屏幕录制权限）
    func debugSnapshot(to path: String) {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
