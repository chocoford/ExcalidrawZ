import SwiftUI
import LLMCore

/// Provider-reported sources. Opening the list never fetches the linked pages.
struct AssistantSourceLinks: View {
    let citations: [LLMSourceCitation]
    @State private var showsSources = false

    private var sources: [LLMSourceCitation] { AISourceCitationStorage.normalized(citations) }

    var body: some View {
        if !sources.isEmpty {
            Button { showsSources = true } label: {
                Label(String(format: String(localized: "AI.Sources.count"), sources.count), systemImage: "link")
                    .font(.footnote)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(.regularMaterial) }
            }
            .buttonStyle(.plain)
            .labelStyle(.titleAndIcon)
            .popover(isPresented: $showsSources) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(localized: "AI.Sources.title")).font(.headline)
                        ForEach(sources) { source in
                            Link(destination: source.url) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.title.flatMap { $0.isEmpty ? nil : $0 } ?? source.url.absoluteString)
                                            .font(.callout).lineLimit(2)
                                        Text(source.url.host ?? source.url.absoluteString)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(source.url.absoluteString)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 320, height: min(380, CGFloat(sources.count) * 64 + 64))
            }
        }
    }
}
