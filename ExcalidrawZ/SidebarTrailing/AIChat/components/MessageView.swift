//
//  MessageView.swift
//  LLMDemo
//
//  Created by Chocoford on 9/5/25.
//

import SwiftUI
import LLMCore
import LLMKit
import ChocofordUI
import ChocofordEssentials
import Shimmer

enum ChatMessageContentFileValue {
    case image(Image)
}

struct MessageView: View {
    var message: ChatMessage
    var displayText: String?
    var onRegenerate: ((String) -> Void)?
    var isActiveStep: Bool = false

    @State private var isExpanded: Bool = false

    private var shouldCollapse: Bool {
        switch message {
            case .content:
                return false
            case .loading, .error, .agentStep:
                return true
        }
    }
    
    var body: some View {
        if shouldCollapse {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(collapsedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .shimmering(active: shouldShimmerCollapsedTitle)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    messageBody
                }
            }
        } else {
            messageBody
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        ZStack {
            switch message {
                case .loading:
                    Text("Thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .shimmering(active: true)
                case .error(_, let error):
                    Text("\(error)")
                        .padding()
                        .foregroundStyle(.red)
                        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                case .content(let content):
                    contentMessage(message: content, displayText: displayText)
                case .agentStep(let step):
                    agentStepView(step: step, displayText: displayText)
            }
        }
    }

    private var collapsedTitle: String {
        switch message {
            case .loading:
                return "Thinking"
            case .error:
                return "Error"
            case .agentStep(let step):
                switch step.type {
                    case .thought:
                        return "Thinking"
                    case .observation:
                        return "Observe output"
                    default:
                        if let title = step.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return title
                        }
                        return "Step: \(stepTitle(for: step.type))"
                }
            case .content(let content):
                return content.role == .user ? "User Message" : "Message"
        }
    }

    private var shouldShimmerCollapsedTitle: Bool {
        switch message {
            case .loading:
                return true
            case .agentStep:
                return isActiveStep
            default:
                return false
        }
    }
    
    @MainActor @ViewBuilder
    private func agentStepView(step: AgentStep, displayText: String?) -> some View {
        let resolvedContent = displayText ?? step.content
        let trimmedTitle = step.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle: String = {
            switch step.type {
                case .thought:
                    "Thinking"
                case .observation:
                    "Observe output"
                default:
                    trimmedTitle.isEmpty ? stepTitle(for: step.type) : trimmedTitle
            }
        }()
        let shouldShimmerTitle = isActiveStep
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Icon based on step type
                Image(systemName: stepIcon(for: step.type))
                    .foregroundStyle(stepColor(for: step.type))
                    .font(.caption)

                Text(displayTitle + "\(shouldShimmerTitle ? "(active)" : "")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(stepColor(for: step.type))
                    .shimmering(active: shouldShimmerTitle)

                Spacer()

                Text(step.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !resolvedContent.isEmpty {
                Text(resolvedContent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)  // Indent content to align with text after icon
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(stepColor(for: step.type).opacity(0.1))
        .cornerRadius(8)
        .padding(.leading, 4)
    }

    private func stepIcon(for type: AgentStep.StepType) -> String {
        switch type {
            case .thought: return "brain"
            case .action: return "hammer.fill"
            case .observation: return "eye.fill"
            case .plan: return "list.bullet.clipboard"
            case .reflection: return "sparkles"
            // default: return ""
        }
    }

    private func stepTitle(for type: AgentStep.StepType) -> String {
        switch type {
            case .thought: return "Thinking"
            case .action: return "Action"
            case .observation: return "Observe output"
            case .plan: return "Planning"
            case .reflection: return "Reflection"
            // default: return "Unknown"
        }
    }
    
    private func stepColor(for type: AgentStep.StepType) -> Color {
        switch type {
            case .thought: return .blue
            case .action: return .purple
            case .observation: return .green
            case .plan: return .orange
            case .reflection: return .pink
            // default: return .gray
        }
    }

    @MainActor @ViewBuilder
    private func contentMessage(message: ChatMessageContent, displayText: String?) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    content(message: message, displayText: displayText)
                }
            } else if message.role == .assistant {
                VStack(alignment: .leading, spacing: 4) {
                    content(message: message, displayText: displayText)
                    assistantMessageActions(for: message, displayText: displayText)
                }
                Spacer()
            }
        }
    }

    @MainActor @ViewBuilder
    private func assistantMessageActions(
        for message: ChatMessageContent,
        displayText: String?
    ) -> some View {
        HStack(spacing: 0) {
            // Copy button
            Button {
                copyToClipboard(displayText ?? message.content ?? "")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .help("Copy message")

            // Regenerate button
            if let onRegenerate {
                Button {
                    onRegenerate(message.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .help("Regenerate response")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.text(size: .small, square: true))
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }

    @MainActor @ViewBuilder
    private func content(message: ChatMessageContent, displayText: String?) -> some View {
        let resolvedText = displayText ?? message.content
        if let text = resolvedText, !text.isEmpty {
            Text(text)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
        }
        
        if let usage = message.usage {
            HStack(spacing: 4) {
                Image(systemName: "bolt.circle")
                Text(usage.consumed.formatted())
            }
            .font(.footnote)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(.regularMaterial)
            }
        }
        
        HStack(spacing: 6) {
            let imageFiles = (message.files ?? []).filter {
                if case .base64EncodedImage = $0 {
                    return true
                }
                if case .image = $0 {
                    return true
                }
                return false
            }
            ForEach(imageFiles, id: \.self) { file in
                MessageImageView(file: file)
            }
        }
    }
}

struct MessageImageView: View {
    var file: ChatMessageContent.File
    
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .cornerRadius(8)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        Task.detached {
            var image: Image? = nil
            if case .base64EncodedImage(let base64) = file {
                if let base64ContentString = base64.components(separatedBy: ",").last,
                   let data = Data(base64Encoded: base64ContentString),
                   let uiImage = PlatformImage(data: data) {
                    image = Image(platformImage: uiImage)
                }
            } else if case .image(let url) = file {
                if let data = try? Data(contentsOf: url),
                   let nsImage = PlatformImage(data: data) {
                    image = Image(platformImage: nsImage)
                }
            }
            if let image {
                await MainActor.run {
                    self.image = image
                }
            }
        }
    }
}
