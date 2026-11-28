import Foundation
import UIKit

// MARK: - Wire Event Payloads

private struct IncomingEnvelope: Decodable {
    let type: String
}

private struct HelloEvent: Decodable {
    let host: String?
    let defaultCwd: String?
    let agentName: String?
    let agentVersion: String?
    let tier: String?
    let activeSessionId: String?
    let activeCwd: String?
    let activeTitle: String?
    let configOptions: [ConfigOption]?
    let availableCommands: [SlashCommandItem]?
    let sessions: [SessionSummary]?
    let messages: [ChatMessage]?
    let pendingPermissions: [PermissionRequest]?
    let usage: UsageInfo?
    let isGenerating: Bool?
}

private struct SessionReadyEvent: Decodable {
    let sessionId: String
    let cwd: String?
    let title: String?
    let configOptions: [ConfigOption]?
    let availableCommands: [SlashCommandItem]?
    let messages: [ChatMessage]?
    let usage: UsageInfo?
    let isGenerating: Bool?
}

private struct SessionsListEvent: Decodable {
    let sessions: [SessionSummary]
}

private struct MessageChunkEvent: Decodable {
    let sessionId: String
    let role: String
    let text: String
}

private struct ToolCallEvent: Decodable {
    let sessionId: String
    let toolCall: ToolCallItem
}

private struct SessionMetaEvent: Decodable {
    let sessionId: String
    let title: String?
    let usage: UsageInfo?
    let configOptions: [ConfigOption]?
    let availableCommands: [SlashCommandItem]?
}

private struct PermissionResolvedEvent: Decodable {
    let requestId: String
}

private struct TurnEvent: Decodable {
    let sessionId: String
    let stopReason: String?
    let error: String?
}

private struct ErrorEvent: Decodable {
    let message: String
}

// MARK: - BridgeClient

@MainActor
final class BridgeClient: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var hostName: String = ""
    @Published var agentVersion: String = ""
    @Published var tierName: String?
    @Published var defaultCwd: String = ""

    @Published var activeSessionId: String?
    @Published var activeCwd: String = ""
    @Published var activeTitle: String = "Antigravity"
    @Published var messages: [ChatMessage] = []
    @Published var sessions: [SessionSummary] = []
    @Published var configOptions: [ConfigOption] = []
    @Published var availableCommands: [SlashCommandItem] = []
    @Published var pendingPermissions: [PermissionRequest] = []
    @Published var usage: UsageInfo = UsageInfo(used: 0, size: 1048576)
    @Published var isGenerating: Bool = false
    @Published var lastError: String?

    private(set) var currentProfile: ServerProfile?
    private var urlSession: URLSession
    private var wsTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var manualDisconnect: Bool = false

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Connection Lifecycle

    func connect(to profile: ServerProfile) {
        manualDisconnect = false
        currentProfile = profile
        reconnectAttempt = 0
        reconnectTask?.cancel()
        openSocket()
    }

    func disconnect() {
        manualDisconnect = true
        teardownSocket()
        connectionState = .disconnected
    }

    func reconnectIfNeeded() {
        guard !manualDisconnect, currentProfile != nil else { return }
        if !connectionState.isConnected {
            reconnectAttempt = 0
            openSocket()
        } else {
            sendRaw(["type": "ping"])
        }
    }

    private func teardownSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
    }

    private func openSocket() {
        teardownSocket()
        guard let profile = currentProfile else {
            connectionState = .disconnected
            return
        }

        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        let wsBase: String
        if normalized.lowercased().hasPrefix("https://") {
            wsBase = "wss://" + String(normalized.dropFirst(8))
        } else if normalized.lowercased().hasPrefix("http://") {
            wsBase = "ws://" + String(normalized.dropFirst(7))
        } else {
            wsBase = "ws://" + normalized
        }

        guard var comps = URLComponents(string: wsBase + "/ws") else {
            connectionState = .error("URL không hợp lệ")
            return
        }
        comps.queryItems = [URLQueryItem(name: "token", value: profile.token)]
        guard let wsURL = comps.url else {
            connectionState = .error("URL WebSocket lỗi")
            return
        }

        connectionState = .connecting
        lastError = nil

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        wsTask = task
        task.resume()

        startReceiveLoop(for: task)
        startPingLoop(for: task)
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self = self else { return }
                    switch message {
                    case .string(let text):
                        self.handleIncoming(text: text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleIncoming(text: text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    guard let self = self else { return }
                    if !Task.isCancelled && self.wsTask === task {
                        self.handleDisconnect(error: error)
                    }
                    return
                }
            }
        }
    }

    private func startPingLoop(for task: URLSessionWebSocketTask) {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self = self, self.wsTask === task else { return }
                self.sendRaw(["type": "ping"])
            }
        }
    }

    private func handleDisconnect(error: Error) {
        wsTask = nil
        pingTask?.cancel()
        receiveTask?.cancel()

        if manualDisconnect {
            connectionState = .disconnected
            return
        }

        let errDesc = error.localizedDescription
        connectionState = .error("Mất kết nối — thử lại...")
        lastError = errDesc

        reconnectAttempt += 1
        let delaySec = min(8.0, 1.5 * Double(reconnectAttempt))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            guard !Task.isCancelled, let self = self, !self.manualDisconnect else { return }
            self.openSocket()
        }
    }

    // MARK: - Outgoing Actions

    private func sendRaw(_ dict: [String: Any]) {
        guard let wsTask = wsTask,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        wsTask.send(.string(text)) { _ in }
    }

    func sendPrompt(text: String, images: [AttachedImage] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }

        // Optimistically display user message immediately for zero-lag feel
        let userMsg = ChatMessage(
            role: "user",
            text: trimmed.isEmpty ? "[Ảnh đính kèm]" : trimmed,
            imageCount: images.count
        )
        messages.append(userMsg)
        isGenerating = true

        let encodedImages: [[String: String]] = images.map { img in
            [
                "data": img.data.base64EncodedString(),
                "mimeType": img.mimeType
            ]
        }

        var payload: [String: Any] = [
            "type": "prompt",
            "text": trimmed,
            "images": encodedImages
        ]
        if let sid = activeSessionId {
            payload["sessionId"] = sid
        }
        sendRaw(payload)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func cancelGeneration() {
        var payload: [String: Any] = ["type": "cancel"]
        if let sid = activeSessionId {
            payload["sessionId"] = sid
        }
        sendRaw(payload)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func requestSessionList() {
        sendRaw(["type": "list_sessions"])
    }

    func createNewSession(cwd: String? = nil) {
        var payload: [String: Any] = ["type": "new_session"]
        let target = cwd ?? (activeCwd.isEmpty ? defaultCwd : activeCwd)
        if !target.isEmpty {
            payload["cwd"] = target
        }
        sendRaw(payload)
    }

    func loadSession(_ summary: SessionSummary) {
        sendRaw([
            "type": "load_session",
            "sessionId": summary.sessionId,
            "cwd": summary.cwd
        ])
    }

    func setConfig(configId: String, value: String) {
        guard let sid = activeSessionId else { return }
        sendRaw([
            "type": "set_config",
            "sessionId": sid,
            "configId": configId,
            "value": value
        ])
    }

    func respondPermission(requestId: String, optionId: String?, cancelled: Bool = false) {
        pendingPermissions.removeAll { $0.requestId == requestId }
        var payload: [String: Any] = [
            "type": "permission_response",
            "requestId": requestId,
            "cancelled": cancelled
        ]
        if let optionId = optionId {
            payload["optionId"] = optionId
        }
        sendRaw(payload)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - REST Helpers

    func testConnection(baseURL: String, token: String) async -> Result<String, Error> {
        let normalized = PairingParser.normalizeBaseURL(baseURL)
        guard let url = URL(string: normalized + "/api/info") else {
            return .failure(NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Địa chỉ URL không hợp lệ"]))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .failure(NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "Phản hồi không hợp lệ"]))
            }
            if http.statusCode == 401 {
                return .failure(NSError(domain: "Bridge", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sai Auth Token"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(domain: "Bridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Lỗi HTTP \(http.statusCode)"]))
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let host = json["host"] as? String {
                return .success(host)
            }
            return .success("PC")
        } catch {
            return .failure(error)
        }
    }

    func listRemoteDirectory(path: String?) async throws -> DirectoryListing {
        guard let profile = currentProfile else {
            throw NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối máy tính"])
        }
        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        guard var comps = URLComponents(string: normalized + "/api/fs/list") else {
            throw NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        if let path = path, !path.isEmpty {
            comps.queryItems = [URLQueryItem(name: "path", value: path)]
        }
        guard let url = comps.url else {
            throw NSError(domain: "Bridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Bridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc thư mục trên PC"])
        }
        return try JSONDecoder().decode(DirectoryListing.self, from: data)
    }

    func browseRemoteDirectory(path: String?, sortBy: String = "recent") async throws -> DirectoryListing {
        guard let profile = currentProfile else {
            throw NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối máy tính"])
        }
        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        guard var comps = URLComponents(string: normalized + "/api/fs/browse") else {
            throw NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var items = [URLQueryItem(name: "sort", value: sortBy)]
        if let path = path, !path.isEmpty {
            items.append(URLQueryItem(name: "path", value: path))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            throw NSError(domain: "Bridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Bridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không thể duyệt tệp trên PC (hãy cập nhật Bridge Server trên PC)"])
        }
        return try JSONDecoder().decode(DirectoryListing.self, from: data)
    }

    func readRemoteFile(path: String) async throws -> FileReadResponse {
        guard let profile = currentProfile else {
            throw NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối máy tính"])
        }
        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        guard var comps = URLComponents(string: normalized + "/api/fs/read") else {
            throw NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = comps.url else {
            throw NSError(domain: "Bridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Bridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc nội dung tệp"])
        }
        return try JSONDecoder().decode(FileReadResponse.self, from: data)
    }

    func downloadRemoteFileData(path: String) async throws -> Data {
        guard let profile = currentProfile else {
            throw NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối máy tính"])
        }
        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        guard var comps = URLComponents(string: normalized + "/api/fs/raw") else {
            throw NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = comps.url else {
            throw NSError(domain: "Bridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 600
        req.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Bridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không thể tải tệp từ PC"])
        }
        return data
    }

    func uploadRemoteFile(localURL: URL, filename: String, targetDirectory: String?) async throws -> FileUploadResponse {
        guard let profile = currentProfile else {
            throw NSError(domain: "Bridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối máy tính"])
        }
        let normalized = PairingParser.normalizeBaseURL(profile.baseURL)
        guard var comps = URLComponents(string: normalized + "/api/fs/upload") else {
            throw NSError(domain: "Bridge", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }
        var items = [URLQueryItem(name: "filename", value: filename)]
        if let dir = targetDirectory, !dir.isEmpty {
            items.append(URLQueryItem(name: "dir", value: dir))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            throw NSError(domain: "Bridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("Bearer \(profile.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await urlSession.upload(for: req, fromFile: localURL)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "Bridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "Phản hồi máy tính không hợp lệ"])
        }
        guard http.statusCode == 200 else {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errJson["error"] as? String {
                throw NSError(domain: "Bridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw NSError(domain: "Bridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Tải tệp lên thất bại (HTTP \(http.statusCode))"])
        }
        return try JSONDecoder().decode(FileUploadResponse.self, from: data)
    }

    // MARK: - Incoming Event Handling

    private func ensureStreamingAssistantIndex() -> Int {
        if let lastIdx = messages.indices.last,
           messages[lastIdx].role == "assistant",
           messages[lastIdx].streaming {
            return lastIdx
        }
        let msg = ChatMessage(role: "assistant", text: "", streaming: true)
        messages.append(msg)
        return messages.count - 1
    }

    private func handleIncoming(text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? JSONDecoder().decode(IncomingEnvelope.self, from: data) else {
            return
        }

        let decoder = JSONDecoder()

        switch env.type {
        case "hello":
            guard let ev = try? decoder.decode(HelloEvent.self, from: data) else { return }
            connectionState = .connected
            reconnectAttempt = 0
            hostName = ev.host ?? currentProfile?.name ?? "Windows PC"
            agentVersion = ev.agentVersion ?? ""
            tierName = ev.tier
            defaultCwd = ev.defaultCwd ?? ""
            activeSessionId = ev.activeSessionId
            activeCwd = ev.activeCwd ?? defaultCwd
            activeTitle = ev.activeTitle ?? "New Chat"
            configOptions = ev.configOptions ?? []
            availableCommands = ev.availableCommands ?? []
            sessions = ev.sessions ?? []
            messages = ev.messages ?? []
            pendingPermissions = ev.pendingPermissions ?? []
            if let u = ev.usage { usage = u }
            isGenerating = ev.isGenerating ?? false

        case "session_ready":
            guard let ev = try? decoder.decode(SessionReadyEvent.self, from: data) else { return }
            activeSessionId = ev.sessionId
            if let cwd = ev.cwd { activeCwd = cwd }
            activeTitle = ev.title ?? "New Chat"
            if let opts = ev.configOptions { configOptions = opts }
            if let cmds = ev.availableCommands { availableCommands = cmds }
            messages = ev.messages ?? []
            if let u = ev.usage { usage = u }
            isGenerating = ev.isGenerating ?? false

        case "sessions_list":
            guard let ev = try? decoder.decode(SessionsListEvent.self, from: data) else { return }
            sessions = ev.sessions

        case "message_chunk":
            guard let ev = try? decoder.decode(MessageChunkEvent.self, from: data),
                  ev.sessionId == activeSessionId else { return }
            if ev.role == "user" { return }
            let idx = ensureStreamingAssistantIndex()
            if ev.role == "thought" {
                messages[idx].thought += ev.text
            } else {
                messages[idx].text += ev.text
            }

        case "tool_call":
            guard let ev = try? decoder.decode(ToolCallEvent.self, from: data),
                  ev.sessionId == activeSessionId else { return }
            let idx = ensureStreamingAssistantIndex()
            if let tcIdx = messages[idx].toolCalls.firstIndex(where: { $0.toolCallId == ev.toolCall.toolCallId }) {
                messages[idx].toolCalls[tcIdx] = ev.toolCall
            } else {
                messages[idx].toolCalls.append(ev.toolCall)
            }

        case "session_meta":
            guard let ev = try? decoder.decode(SessionMetaEvent.self, from: data),
                  ev.sessionId == activeSessionId else { return }
            if let t = ev.title, !t.isEmpty { activeTitle = t }
            if let u = ev.usage { usage = u }
            if let opts = ev.configOptions { configOptions = opts }
            if let cmds = ev.availableCommands { availableCommands = cmds }

        case "permission_request":
            guard let req = try? decoder.decode(PermissionRequest.self, from: data) else { return }
            if !pendingPermissions.contains(where: { $0.requestId == req.requestId }) {
                pendingPermissions.append(req)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                NotificationManager.shared.notifyIfBackgrounded(
                    title: "Antigravity cần duyệt lệnh",
                    body: req.toolCall.title
                )
            }

        case "permission_resolved":
            guard let ev = try? decoder.decode(PermissionResolvedEvent.self, from: data) else { return }
            pendingPermissions.removeAll { $0.requestId == ev.requestId }

        case "turn_started":
            guard let ev = try? decoder.decode(TurnEvent.self, from: data),
                  ev.sessionId == activeSessionId else { return }
            isGenerating = true

        case "turn_finished":
            guard let ev = try? decoder.decode(TurnEvent.self, from: data),
                  ev.sessionId == activeSessionId else { return }
            isGenerating = false
            for i in messages.indices {
                messages[i].streaming = false
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationManager.shared.notifyIfBackgrounded(
                title: "Antigravity đã trả lời xong",
                body: activeTitle
            )

        case "error":
            guard let ev = try? decoder.decode(ErrorEvent.self, from: data) else { return }
            lastError = ev.message
            isGenerating = false
            for i in messages.indices { messages[i].streaming = false }
            messages.append(ChatMessage(role: "assistant", text: "⚠️ \(ev.message)"))

        case "pong":
            if !connectionState.isConnected {
                connectionState = .connected
            }

        default:
            break
        }
    }

    // Convenience config accessors
    var modelConfig: ConfigOption? {
        configOptions.first(where: { $0.id == "model" })
    }

    var thoughtConfig: ConfigOption? {
        configOptions.first(where: { $0.id == "thought_level" })
    }

    var modeConfig: ConfigOption? {
        configOptions.first(where: { $0.id == "mode" })
    }
}
