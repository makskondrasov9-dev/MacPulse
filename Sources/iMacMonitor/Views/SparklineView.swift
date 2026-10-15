import AppKit
import MonitorCore
import SwiftUI

/// No animations, timers or Charts layout; at most twelve path points per sample.
struct SparklineView: View {
    let readings: [Double?]
    var maximum: Double? = nil
    var color: Color = .primary
    // MenuBarExtra reliably supports Image/Text labels. Render the tiny Path as
    // a template image so native menu bar tinting works in both appearances.
    @MainActor static func image(cpu: [Double?]?, network: [Double?]?, showIcon: Bool) -> NSImage {
        let renderer = ImageRenderer(content: HStack(spacing: 5) {
            if showIcon { Image(systemName: "desktopcomputer").font(.system(size: 14)) }
            if let cpu { SparklineView(readings: cpu, maximum: 100) }
            if let network { SparklineView(readings: network) }
        }.fixedSize().environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 12))
        image.isTemplate = true
        return image
    }
    var body: some View {
        Path { path in
            var connected = false
            for point in SparklineGeometry.points(readings, maximum: maximum) {
                guard let point else { connected = false; continue }
                let position = CGPoint(x: 1 + point.x * 20, y: 1 + point.y * 10)
                if connected { path.addLine(to: position) }
                else { path.move(to: position); path.addLine(to: position) }
                connected = true
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        .frame(width: 22, height: 12)
        .overlay { if !readings.suffix(12).contains(where: { $0.map { $0.isFinite && $0 >= 0 } ?? false }) { Text("—").font(.system(size: 8)) } }
        .environment(\.layoutDirection, .leftToRight)
    }
}
