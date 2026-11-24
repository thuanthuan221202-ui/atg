import Foundation

struct ServerProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var token: String

    init(id: UUID = UUID(), name: String, baseURL: String, token: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.token = token
    }
}

struct UsageInfo: Codable, Equatable {
    var used: Int
    var size: Int

    var fraction: Double {
        guard size > 0 else { return 0 }
        return min(1.0, max(0.0, Double(used) / Double(size)))
    }

    var formattedUsed: String {
        if used >= 1000 {
            return String(format: "%.1fk", Double(used) / 1000.0)
        }
        return "\(used)"
    }
}

struct ToolCallItem: Identifiable, Codable, Equatable {
    var id: String { toolCallId }
    var toolCallId: String
    var name: String
    var title: String
    var kind: String
    var status: String
    var inputSummary: String
    var outputText: String

    enum CodingKeys: String, CodingKey {
        case toolCallId, name, title, kind, status, inputSummary, outputText
    }

    init(
        toolCallId: String,
        name: String,
        title: String,
        kind: String = "other",
        status: String = "in_progress",
        inputSummary: String = "",
        outputText: String = ""
    ) {
        self.toolCallId = toolCallId
        self.name = name
        self.title = title
        self.kind = kind
        self.status = status
        self.inputSummary = inputSummary
        self.outputText = outputText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "tool"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? name
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "in_progress"
        inputSummary = try c.decodeIfPresent(String.self, forKey: .inputSummary) ?? ""
        outputText = try c.decodeIfPresent(String.self, forKey: .outputText) ?? ""
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: String
    var role: String // "user" | "assistant"
    var text: String
    var thought: String
    var toolCalls: [ToolCallItem]
    var imageCount: Int
    var streaming: Bool
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case id, role, text, thought, toolCalls, imageCount, streaming, timestamp
    }

    init(
        id: String = UUID().uuidString,
        role: String,
        text: String,
        thought: String = "",
        toolCalls: [ToolCallItem] = [],
        imageCount: Int = 0,
        streaming: Bool = false,
        timestamp: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thought = thought
        self.toolCalls = toolCalls
        self.imageCount = imageCount
        self.streaming = streaming
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        thought = try c.decodeIfPresent(String.self, forKey: .thought) ?? ""
        toolCalls = try c.decodeIfPresent([ToolCallItem].self, forKey: .toolCalls) ?? []
        imageCount = try c.decodeIfPresent(Int.self, forKey: .imageCount) ?? 0
        streaming = try c.decodeIfPresent(Bool.self, forKey: .streaming) ?? false
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp) ?? (Date().timeIntervalSince1970 * 1000)
    }
}

struct PermissionToolCall: Codable, Equatable {
    var toolCallId: String
    var name: String
    var title: String
    var kind: String
    var inputSummary: String

    enum CodingKeys: String, CodingKey {
        case toolCallId, name, title, kind, inputSummary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "tool"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? name
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "execute"
        inputSummary = try c.decodeIfPresent(String.self, forKey: .inputSummary) ?? ""
    }
}

struct PermissionOption: Identifiable, Codable, Equatable {
    var id: String { optionId }
    var optionId: String
    var name: String
    var kind: String

    var isReject: Bool {
        kind.lowercased().contains("reject") || optionId.lowercased().contains("deny")
    }
}

struct PermissionRequest: Identifiable, Codable, Equatable {
    var id: String { requestId }
    var requestId: String
    var sessionId: String
    var toolCall: PermissionToolCall
    var options: [PermissionOption]
}

struct ConfigOptionChoice: Identifiable, Codable, Equatable {
    var id: String { value }
    var value: String
    var name: String
    var description: String?
}

struct ConfigOption: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var category: String?
    var currentValue: String
    var options: [ConfigOptionChoice]

    var currentDisplayName: String {
        options.first(where: { $0.value == currentValue })?.name ?? currentValue
    }
}

struct SessionSummary: Identifiable, Codable, Equatable {
    var id: String { sessionId }
    var sessionId: String
    var cwd: String
    var title: String
    var updatedAt: String
}

struct SlashCommandItem: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var description: String
}

struct DirectoryEntry: Identifiable, Codable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
}

struct DirectoryListing: Codable {
    var path: String
    var parent: String?
    var drives: [String]
    var entries: [DirectoryEntry]
    var error: String?
}

struct AttachedImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let mimeType: String
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .disconnected: return "Chưa kết nối"
        case .connecting: return "Đang kết nối..."
        case .connected: return "Đã kết nối"
        case .error(let msg): return msg
        }
    }
}

// MARK: - Pairing URI Helper

struct PairingPayload {
    let url: String
    let token: String
    let name: String
}

enum PairingParser {
    static func parse(_ raw: String) -> PairingPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "agyr",
              let items = components.queryItems else {
            return nil
        }
        guard let urlVal = items.first(where: { $0.name == "url" })?.value,
              let tokenVal = items.first(where: { $0.name == "token" })?.value,
              !urlVal.isEmpty, !tokenVal.isEmpty else {
            return nil
        }
        let nameVal = items.first(where: { $0.name == "name" })?.value ?? "Windows PC"
        return PairingPayload(url: urlVal, token: tokenVal, name: nameVal)
    }

    static func normalizeBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }
}
