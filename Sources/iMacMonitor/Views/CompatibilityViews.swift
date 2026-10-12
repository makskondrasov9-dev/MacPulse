import SwiftUI

/// Preserve initial delivery and subsequent updates on Ventura as well as Sonoma.
extension View {
    @ViewBuilder func onInitialChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value, initial: true) { _, newValue in action(newValue) }
        } else {
            onAppear { action(value) }.onChange(of: value, perform: action)
        }
    }
}

struct CompatibleEmptyState: View {
    let title: String
    let systemImage: String
    var description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 36)).foregroundStyle(.secondary)
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                description?.foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .accessibilityElement(children: .combine)
        }
    }
}
