import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == "user" {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if message.imageCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                        Text("\(message.imageCount) ảnh đính kèm")
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundColor(.white)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.cyan)
                Text("Antigravity")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
                if message.streaming {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(AppTheme.cyan)
                }
                Spacer()
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }

            // Collapsible thought box
            if !message.thought.isEmpty {
                ThoughtDisclosureCard(text: message.thought, isStreaming: message.streaming && message.text.isEmpty)
            }

            // Tool calls
            if !message.toolCalls.isEmpty {
                VStack(spacing: 8) {
                    ForEach(message.toolCalls) { tc in
                        ToolCallCard(toolCall: tc)
                    }
                }
            }

            // Markdown + Code blocks body
            if !message.text.isEmpty {
                MarkdownContentView(text: message.text)
            } else if message.streaming && message.toolCalls.isEmpty && message.thought.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppTheme.cyan)
                    Text("Đang suy nghĩ...")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Collapsible Thought Card

private struct ThoughtDisclosureCard: View {
    let text: String
    let isStreaming: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                    Text(isStreaming ? "Đang suy luận..." : "Quá trình suy luận")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            if expanded {
                Text(text)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .background(AppTheme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border.opacity(0.75), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Tool Call Card

private struct ToolCallCard: View {
    let toolCall: ToolCallItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(toolCall.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text(toolCall.name)
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    statusBadge
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            if expanded {
                if !toolCall.inputSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("INPUT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(toolCall.inputSummary)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.cyan)
                                .textSelection(.enabled)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if !toolCall.outputText.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OUTPUT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Text(toolCall.outputText)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary.opacity(0.9))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(10)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconName: String {
        switch toolCall.kind.lowercased() {
        case "execute", "terminal": return "terminal.fill"
        case "edit", "write": return "pencil.line"
        case "read": return "doc.text.fill"
        case "search", "fetch": return "magnifyingglass"
        default: return "wrench.and.screwdriver.fill"
        }
    }

    private var statusColor: Color {
        switch toolCall.status.lowercased() {
        case "completed": return AppTheme.green
        case "failed", "error": return AppTheme.red
        case "pending": return AppTheme.amber
        default: return AppTheme.cyan
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch toolCall.status.lowercased() {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(AppTheme.green)
        case "failed", "error":
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(AppTheme.red)
        case "pending":
            Text("Chờ duyệt")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.amber)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.amber.opacity(0.18))
                .clipShape(Capsule())
        default:
            ProgressView()
                .scaleEffect(0.65)
                .tint(AppTheme.cyan)
        }
    }
}

// MARK: - Native Markdown + Fenced Code Renderer (iOS 16+)

private enum ContentBlock: Identifiable {
    case prose(id: Int, text: String)
    case code(id: Int, language: String, code: String)

    var id: Int {
        switch self {
        case .prose(let id, _): return id
        case .code(let id, _, _): return id
        }
    }
}

private struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .prose(_, let prose):
                    proseView(prose)
                case .code(_, let lang, let code):
                    CodeBlockCard(language: lang, code: code)
                }
            }
        }
    }

    @ViewBuilder
    private func proseView(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let attr = try? AttributedString(
                markdown: trimmed,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attr)
                    .font(.body)
                    .foregroundColor(AppTheme.textPrimary)
                    .tint(AppTheme.cyan)
                    .textSelection(.enabled)
            } else {
                Text(trimmed)
                    .font(.body)
                    .foregroundColor(AppTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    private func parseBlocks(_ input: String) -> [ContentBlock] {
        var result: [ContentBlock] = []
        let lines = input.components(separatedBy: "\n")
        var inCode = false
        var codeLang = ""
        var buffer: [String] = []
        var idx = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if !inCode {
                    if !buffer.isEmpty {
                        result.append(.prose(id: idx, text: buffer.joined(separator: "\n")))
                        idx += 1
                        buffer.removeAll()
                    }
                    inCode = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else {
                    result.append(.code(id: idx, language: codeLang, code: buffer.joined(separator: "\n")))
                    idx += 1
                    buffer.removeAll()
                    inCode = false
                    codeLang = ""
                }
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            if inCode {
                result.append(.code(id: idx, language: codeLang, code: buffer.joined(separator: "\n")))
            } else {
                result.append(.prose(id: idx, text: buffer.joined(separator: "\n")))
            }
        }

        return result
    }
}

private struct CodeBlockCard: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Đã chép" : "Chép")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(copied ? AppTheme.green : AppTheme.cyan)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.card)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Color(red: 0.85, green: 0.91, blue: 0.98))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(AppTheme.codeBg)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
