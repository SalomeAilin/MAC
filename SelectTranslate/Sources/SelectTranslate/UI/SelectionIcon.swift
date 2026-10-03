import AppKit

/// 选中文字后出现在鼠标旁的小图标，点击即翻译，几秒后自动消失
final class SelectionIconController {
    /// text 为 nil 时需要在点击后再读取选区
    var onClick: ((String?, NSPoint) -> Void)?

    private static let size: CGFloat = 28
    private var panel: NSPanel?
    private var text: String?
    private var location: NSPoint = .zero
    private var hideTask: Task<Void, Never>?

    func show(text: String?, at point: NSPoint) {
        self.text = text
        location = point
        let panel = self.panel ?? makePanel()

        var origin = NSPoint(x: point.x + 8, y: point.y - Self.size - 10)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - Self.size - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - Self.size - 4)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let view = SelectionIconView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.onClick = { [weak self] in
            guard let self else { return }
            self.hide()
            self.onClick?(self.text, self.location)
        }
        view.onHover = { [weak self] hovering in
            if hovering { self?.hideTask?.cancel() } else { self?.scheduleHide() }
        }
        panel.contentView = view
        self.panel = panel
        return panel
    }
}

private final class SelectionIconView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    private var isHovering = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    private static let symbol: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return NSImage(systemSymbolName: "translate", accessibilityDescription: "翻译")?
            .withSymbolConfiguration(configuration)
    }()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let fill: NSColor
        if isPressed {
            fill = accent.shadow(withLevel: 0.2) ?? accent
        } else if isHovering {
            fill = accent.highlight(withLevel: 0.15) ?? accent
        } else {
            fill = accent
        }
        fill.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()

        guard let symbol = Self.symbol else { return }
        let size = symbol.size
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        symbol.draw(in: rect)
    }
}
