import SwiftUI
import SFSafeSymbols

struct InspectorSearchField: View {
    @Binding var text: String
    let prompt: Text

    var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(.secondary)
            TextField("", text: $text, prompt: prompt)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            fieldBackground
        }
    }

    private var fieldBackground: some View {
        Capsule()
            .fill(.clear)
            .background {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Capsule())
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
    }
}
