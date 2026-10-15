import AppKit

@main struct DisplaySmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        DispatchQueue.main.async {
            Task { @MainActor in
                DisplayTestController.shared.show()
                try? await Task.sleep(for: .milliseconds(300))
                guard let window = app.windows.first(where: { $0.isVisible && $0.level == .screenSaver }), let view = window.contentView else { DisplayTestController.shared.close(); print("No display window"); exit(1) }
                precondition(view.accessibilityHelp() != nil, "HUD should be visible at launch")
                let expected: [[CGFloat]] = [[1,0,0],[0,1,0],[0,0,1],[1,1,1],[0,0,0]]
                for (index, rgb) in expected.enumerated() {
                    try? await Task.sleep(for: .milliseconds(600))
                    let rect = NSRect(x: 0, y: 0, width: 2, height: 2)
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: rect)!
                    view.cacheDisplay(in: rect, to: bitmap)
                    var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
                    bitmap.getPixel(&pixel, atX: 0, y: 0)
                    let maxValue = Double((1 << bitmap.bitsPerSample) - 1)
                    let actual = pixel.prefix(3).map { Double($0) / maxValue }
                    guard zip(actual, rgb).allSatisfy({ abs($0.0 - Double($0.1)) < 0.02 }) else {
                        DisplayTestController.shared.close(); print("Color mismatch: \(index), \(actual)"); exit(1)
                    }
                    if index % 2 == 0 {
                        view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                    } else {
                        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!)
                    }
                }
                precondition(view.accessibilityHelp() == nil, "HUD should disappear after three seconds")
                view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
                precondition(!window.isVisible)
                print("Display smoke passed: five RGB colors, timed HUD, click, Space and Escape.")
                app.stop(nil)
                exit(0)
            }
        }
        app.run()
    }
}
