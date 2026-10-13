import AppKit

@MainActor final class DisplayTestController {
    static let shared = DisplayTestController()
    private var window: NSWindow?
    func show() {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let window = PixelWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.colorSpace = screen.colorSpace
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let view = PixelView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.exit = { [weak self] in self?.close() }
        window.contentView = view; self.window = window
        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
    }
    func close() { guard window != nil else { return }; NSCursor.unhide(); window?.orderOut(nil); window?.close(); window = nil }
    private final class PixelWindow: NSWindow { override var canBecomeKey: Bool { true } }
    private final class PixelView: NSView {
        var exit: (() -> Void)?
        private var index = 0
        // Use the display's native profile so each test excites one panel channel,
        // rather than converting an sRGB primary into several wide-gamut channels.
        private let colors: [[CGFloat]] = [[1,0,0,1], [0,1,0,1], [0,0,1,1], [1,1,1,1], [0,0,0,1]]
        override var acceptsFirstResponder: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let space = window?.colorSpace ?? .sRGB
            let color = colors[index].withUnsafeBufferPointer { NSColor(colorSpace: space, components: $0.baseAddress!, count: 4) }
            color.setFill(); bounds.fill()
        }
        override func mouseDown(with event: NSEvent) { advance() }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { exit?() }
            else if event.keyCode == 49 { advance() }
        }
        private func advance() { index = (index + 1) % colors.count; needsDisplay = true }
    }
}
