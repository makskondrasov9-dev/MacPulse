import AppKit

@MainActor final class DisplayTestController {
    static let shared = DisplayTestController()
    private var window: NSWindow?
    func show(instructions: String = "Click or Space — next color • ESC — exit") {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let window = PixelWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.colorSpace = screen.colorSpace
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let view = PixelView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.showInstructions(instructions)
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
        private var instructions: String?
        func showInstructions(_ text: String) {
            instructions = text
            setAccessibilityHelp(text)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.instructions = nil
                self?.setAccessibilityHelp(nil)
                self?.needsDisplay = true
            }
        }
        // Use the display's native profile so each test excites one panel channel,
        // rather than converting an sRGB primary into several wide-gamut channels.
        private let colors: [[CGFloat]] = [[1,0,0,1], [0,1,0,1], [0,0,1,1], [1,1,1,1], [0,0,0,1]]
        override var acceptsFirstResponder: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let space = window?.colorSpace ?? .sRGB
            let color = colors[index].withUnsafeBufferPointer { NSColor(colorSpace: space, components: $0.baseAddress!, count: 4) }
            color.setFill(); bounds.fill()
            if let instructions {
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white]
                let text = NSAttributedString(string: instructions, attributes: attributes)
                let width = min(bounds.width - 48, text.size().width + 40)
                let box = NSRect(x: (bounds.width - width) / 2, y: bounds.height - 100, width: width, height: 64)
                NSColor.black.withAlphaComponent(0.7).setFill()
                NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
                text.draw(in: box.insetBy(dx: 20, dy: 16))
            }
        }
        override func mouseDown(with event: NSEvent) { advance() }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { exit?() }
            else if event.keyCode == 49 { advance() }
        }
        private func advance() { index = (index + 1) % colors.count; needsDisplay = true }
    }
}
