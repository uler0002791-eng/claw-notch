//
//  LobsterStateManager.swift
//  boringNotch
//
//  Manages lobster animation states via WebSocket connection to OpenClaw gateway.
//  Listens for real-time agent + chat events to drive lobster mood and collect messages.
//

import Combine
import Network
import os
import SwiftUI

private let wsLog = Logger(subsystem: "com.boringNotch", category: "LobsterWS")

// MARK: - Mood (3 states for mini view)

enum LobsterMood: String, CaseIterable {
    case idle
    case working
    case offline
}

// MARK: - Detailed activity (for expanded view)

enum LobsterActivity: String {
    case idle       // 💤 Standing by
    case thinking   // 💭 Received message, AI is thinking
    case typing     // ✍️ AI streaming text output
    case toolUse    // 🔧 Calling a tool / function
    case searching  // 🔍 Searching / browsing
    case done       // ✅ Just finished a task
    case error      // ❌ Something went wrong
    case offline    // 📴 Not connected
}

// MARK: - Recent message from WebSocket

struct LobsterRecentMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - State Manager

@MainActor
class LobsterStateManager: ObservableObject {
    static let shared = LobsterStateManager()

    @Published var mood: LobsterMood = .offline
    @Published var activity: LobsterActivity = .offline

    /// Recent messages collected from WebSocket events (last 50, persisted)
    @Published var recentMessages: [LobsterRecentMessage] = []

    private static let messagesKey = "lobsterRecentMessages"
    private static let maxPersistedMessages = 50

    /// Current streaming text being assembled from chat deltas
    @Published var liveText: String = ""

    /// Current run ID being tracked
    private var activeRunId: String?

    /// Idempotency keys for messages sent from the notch (to avoid duplicating them)
    private var sentIdempotencyKeys: Set<String> = []

    /// Active session key — updated dynamically from incoming events
    private var sessionKey = "agent:main:main"

    /// Unique instance ID for this client connection
    private let instanceId = UUID().uuidString

    private var wsTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    private var doneTimer: Task<Void, Never>?

    /// Active WebSocket handle for sending messages
    private var activeWs: URLSessionWebSocketTask?

    /// Network reachability monitor
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    /// The activity before network went down, so we can restore it
    private var activityBeforeOffline: LobsterActivity?

    private let gatewayHost: String
    private let gatewayPort: Int
    private let gatewayToken: String

    private init() {
        NSLog("[LobsterWS] 🦞 LobsterStateManager INIT")
        self.gatewayHost = UserDefaults.standard.string(forKey: "openClawHost") ?? "127.0.0.1"
        let port = UserDefaults.standard.integer(forKey: "openClawPort")
        self.gatewayPort = port == 0 ? 18789 : port
        self.gatewayToken = UserDefaults.standard.string(forKey: "openClawToken") ?? "558f111a274fc00270ebf0e6ae6e36133620fb40a7f57e2d"
        self.recentMessages = Self.loadMessages()
        startNetworkMonitor()
        startWebSocket()
    }

    // MARK: - Network Reachability

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = (path.status == .satisfied)

                if !self.isNetworkAvailable && wasAvailable {
                    // Network just went down
                    NSLog("[LobsterWS] 📴 Network lost — setting offline")
                    self.activityBeforeOffline = self.activity
                    self.setActivity(.offline)
                } else if self.isNetworkAvailable && !wasAvailable {
                    // Network restored
                    NSLog("[LobsterWS] 📶 Network restored")
                    if let prev = self.activityBeforeOffline, prev != .offline {
                        self.setActivity(prev)
                    } else if self.activeWs != nil {
                        self.setActivity(.idle)
                    }
                    self.activityBeforeOffline = nil
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.boringNotch.networkMonitor"))
    }

    var dashboardURL: URL {
        URL(string: "http://\(gatewayHost):\(gatewayPort)")!
    }

    // MARK: - WebSocket Connection

    private func startWebSocket() {
        wsTask?.cancel()
        pingTask?.cancel()
        wsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.connectAndListen()
                self.pingTask?.cancel()
                await MainActor.run { [weak self] in
                    self?.setActivity(.offline)
                }
                let delay = self.reconnectDelay
                self.reconnectDelay = min(self.reconnectDelay * 1.5, 15.0)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func connectAndListen() async {
        let wsURL = URL(string: "ws://\(gatewayHost):\(gatewayPort)")!
        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("http://\(gatewayHost):\(gatewayPort)", forHTTPHeaderField: "Origin")

        let session = URLSession(configuration: .default)
        let wsTaskHandle = session.webSocketTask(with: request)
        wsTaskHandle.resume()

        do {
            // Step 1: Receive challenge
            let challengeMsg = try await wsTaskHandle.receive()
            guard let challengeData = challengeMsg.data,
                  let challenge = try? JSONSerialization.jsonObject(with: challengeData) as? [String: Any],
                  let payload = challenge["payload"] as? [String: Any],
                  let _ = payload["nonce"] as? String else {
                wsTaskHandle.cancel(with: .internalServerError, reason: nil)
                return
            }

            // Step 2: Send connect (with instanceId — required by gateway)
            let connectParams: [String: Any] = [
                "type": "req",
                "id": UUID().uuidString,
                "method": "connect",
                "params": [
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": [
                        "id": "openclaw-macos",
                        "version": "1.0",
                        "platform": "macos",
                        "mode": "webchat",
                        "instanceId": instanceId
                    ] as [String: Any],
                    "role": "operator",
                    "scopes": ["operator.admin"],
                    "auth": [
                        "token": gatewayToken
                    ],
                    "caps": ["tool-events"]
                ] as [String: Any]
            ]
            let connectData = try JSONSerialization.data(withJSONObject: connectParams)
            try await wsTaskHandle.send(.data(connectData))

            // Step 3: Receive hello response
            let helloMsg = try await wsTaskHandle.receive()
            guard let helloData = helloMsg.data,
                  let hello = try? JSONSerialization.jsonObject(with: helloData) as? [String: Any] else {
                NSLog("[LobsterWS] ❌ Failed to parse hello response")
                wsTaskHandle.cancel(with: .internalServerError, reason: nil)
                return
            }

            if hello["ok"] as? Bool != true {
                let errMsg = (hello["error"] as? [String: Any])?["message"] as? String ?? "unknown"
                NSLog("[LobsterWS] ❌ Connect rejected: \(errMsg)")
                wsTaskHandle.cancel(with: .internalServerError, reason: nil)
                return
            }

            // Connected
            reconnectDelay = 1.0
            NSLog("[LobsterWS] ✅ Connected to gateway")
            await MainActor.run { [weak self] in
                self?.activeWs = wsTaskHandle
                self?.setActivity(.idle)
            }

            // Step 3.5: Fetch chat history to sync messages from Feishu/Discord/etc.
            await fetchChatHistory(ws: wsTaskHandle)

            // Step 3.6: Start ping loop for fast offline detection
            pingTask?.cancel()
            pingTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }
                    let ok = await withCheckedContinuation { cont in
                        wsTaskHandle.sendPing { error in
                            cont.resume(returning: error == nil)
                        }
                    }
                    if !ok {
                        NSLog("[LobsterWS] 🏓 Ping failed — connection lost")
                        wsTaskHandle.cancel(with: .goingAway, reason: nil)
                        await MainActor.run { [weak self] in
                            self?.activeWs = nil
                            self?.setActivity(.offline)
                        }
                        break
                    }
                }
            }

            // Step 4: Listen for events
            NSLog("[LobsterWS] 👂 Listening for events...")
            while !Task.isCancelled {
                let message = try await wsTaskHandle.receive()
                guard let data = message.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let msgType = json["type"] as? String ?? ""
                let event = json["event"] as? String ?? ""

                // Handle event messages
                if msgType == "event" {
                    if event == "agent" {
                        let stream = (json["payload"] as? [String: Any])?["stream"] as? String ?? "?"
                        NSLog("[LobsterWS] 📡 agent event: stream=\(stream)")
                        await handleAgentEvent(json)
                    } else if event == "chat" {
                        let state = (json["payload"] as? [String: Any])?["state"] as? String ?? "?"
                        let sk = (json["payload"] as? [String: Any])?["sessionKey"] as? String ?? "?"
                        NSLog("[LobsterWS] 💬 chat event: state=\(state) session=\(sk)")
                        await handleChatEvent(json)
                    }
                }
                // Handle responses (e.g., chat.history response)
                else if msgType == "res" {
                    let ok = json["ok"] as? Bool ?? false
                    NSLog("[LobsterWS] 📩 response ok=\(ok)")
                    await handleResponse(json)
                }
            }

        } catch {
            NSLog("[LobsterWS] ❌ Error: \(error)")
            wsTaskHandle.cancel(with: .goingAway, reason: nil)
            await MainActor.run { [weak self] in
                self?.activeWs = nil
            }
        }
    }

    // MARK: - Fetch Chat History

    private var pendingHistoryRequestIds: Set<String> = []

    private func fetchChatHistory(ws: URLSessionWebSocketTask) async {
        // Fetch history from the main session
        await fetchHistoryForSession(ws: ws, key: "agent:main:main")
    }

    private func fetchHistoryForSession(ws: URLSessionWebSocketTask, key: String) async {
        let reqId = UUID().uuidString
        await MainActor.run { [weak self] in
            self?.pendingHistoryRequestIds.insert(reqId)
        }

        let req: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": "chat.history",
            "params": [
                "sessionKey": key
            ] as [String: Any]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: req)
            try await ws.send(.data(data))
        } catch {
            // History fetch failed, not critical
        }
    }

    private func handleResponse(_ json: [String: Any]) async {
        guard let resId = json["id"] as? String,
              json["ok"] as? Bool == true,
              let payload = json["payload"] as? [String: Any] else { return }

        await MainActor.run { [weak self] in
            guard let self else { return }

            // Handle chat.history response
            if self.pendingHistoryRequestIds.contains(resId) {
                self.pendingHistoryRequestIds.remove(resId)
                self.processChatHistory(payload)
            }
        }
    }

    private func processChatHistory(_ payload: [String: Any]) {
        guard let messages = payload["messages"] as? [[String: Any]] else {
            NSLog("[LobsterWS] ⚠️ chat.history: no messages array in payload")
            return
        }

        NSLog("[LobsterWS] 📜 chat.history: \(messages.count) messages from server")

        // Extract recent user and assistant messages, skip system/heartbeat
        var historyMessages: [LobsterRecentMessage] = []

        for msg in messages {
            guard let role = msg["role"] as? String,
                  role == "user" || role == "assistant" else { continue }

            let timestamp = msg["timestamp"] as? Double ?? 0
            let date = Date(timeIntervalSince1970: timestamp / 1000.0)

            // Extract text content
            var text = ""
            if let content = msg["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let blockText = block["text"] as? String {
                        text += blockText
                    }
                }
            } else if let content = msg["content"] as? String {
                text = content
            }

            // Skip empty, error-only, or heartbeat messages
            if text.isEmpty { continue }
            if text.contains("HEARTBEAT") { continue }
            if text.hasPrefix("Read HEARTBEAT.md") { continue }

            let lobsterRole: LobsterRecentMessage.Role = role == "user" ? .user : .assistant
            historyMessages.append(LobsterRecentMessage(role: lobsterRole, content: text, timestamp: date))
        }

        NSLog("[LobsterWS] 📜 After filtering: \(historyMessages.count) messages")

        if !historyMessages.isEmpty {
            // Simply use the last N messages from server history as the source of truth
            var result = Array(historyMessages.suffix(Self.maxPersistedMessages))
            recentMessages = result
            Self.saveMessages(recentMessages)
            NSLog("[LobsterWS] 📜 Updated recentMessages: \(recentMessages.count) messages")
        }
    }

    // MARK: - Chat Event Handling

    /// Handle real-time chat events (messages from Feishu, Discord, Dashboard, etc.)
    private func handleChatEvent(_ json: [String: Any]) async {
        guard let chatPayload = json["payload"] as? [String: Any] else { return }

        // Track the active session key from incoming events
        if let payloadSessionKey = chatPayload["sessionKey"] as? String,
           !payloadSessionKey.contains("cron:") {
            await MainActor.run { [weak self] in
                self?.sessionKey = payloadSessionKey
            }
        }

        let state = chatPayload["state"] as? String ?? ""
        let message = chatPayload["message"] as? [String: Any]

        await MainActor.run { [weak self] in
            guard let self else { return }

            switch state {
            case "delta":
                // Streaming assistant text
                if let msg = message, let text = self.extractFullText(from: msg) {
                    // Chat deltas send the full accumulated text, not incremental
                    if text.count >= self.liveText.count {
                        self.liveText = text
                    }
                }
                if self.activity != .typing {
                    self.setActivity(.typing)
                }

            case "final":
                // Complete message (user or assistant)
                if let msg = message {
                    let role = msg["role"] as? String ?? ""
                    if let text = self.extractFullText(from: msg), !text.isEmpty {
                        // Skip heartbeat messages
                        if text.contains("HEARTBEAT") || text.hasPrefix("Read HEARTBEAT.md") {
                            break
                        }

                        let lobsterRole: LobsterRecentMessage.Role = role == "user" ? .user : .assistant

                        // Avoid duplicating messages we sent from notch
                        if lobsterRole == .user {
                            // Check if this is a message we sent ourselves
                            let isDuplicate = self.recentMessages.suffix(5).contains { existing in
                                existing.role == .user && existing.content == text
                            }
                            if !isDuplicate {
                                self.appendMessage(role: .user, content: text)
                            }
                        } else {
                            // Assistant message — replace liveText if it matches
                            if !self.liveText.isEmpty {
                                self.liveText = ""
                            }
                            self.appendMessage(role: .assistant, content: text)
                        }
                    }
                }

                // Reset streaming state
                self.liveText = ""
                self.activeRunId = nil

                // Brief "done" flash then idle
                self.setActivity(.done)
                self.doneTimer?.cancel()
                self.doneTimer = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        if self?.activity == .done {
                            self?.setActivity(.idle)
                        }
                    }
                }

            case "aborted":
                // Aborted — save whatever we have
                if !self.liveText.isEmpty {
                    self.appendMessage(role: .assistant, content: self.liveText)
                    self.liveText = ""
                }
                self.activeRunId = nil
                self.setActivity(.idle)

            case "error":
                self.liveText = ""
                self.activeRunId = nil
                self.setActivity(.error)
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run { [weak self] in
                        if self?.activity == .error {
                            self?.setActivity(.idle)
                        }
                    }
                }

            default:
                break
            }
        }
    }

    /// Extract full text content from a message object
    private func extractFullText(from message: [String: Any]) -> String? {
        // Format 1: content is array of blocks [{type: "text", text: "..."}]
        if let content = message["content"] as? [[String: Any]] {
            var texts: [String] = []
            for block in content {
                if let blockType = block["type"] as? String, blockType == "text",
                   let blockText = block["text"] as? String {
                    texts.append(blockText)
                }
            }
            let joined = texts.joined()
            return joined.isEmpty ? nil : joined
        }

        // Format 2: content is a plain string
        if let content = message["content"] as? String {
            return content.isEmpty ? nil : content
        }

        // Format 3: text field directly
        if let text = message["text"] as? String {
            return text.isEmpty ? nil : text
        }

        return nil
    }

    // MARK: - Agent Event Handling

    private func handleAgentEvent(_ json: [String: Any]) async {
        guard let agentPayload = json["payload"] as? [String: Any],
              let stream = agentPayload["stream"] as? String else { return }

        let eventData = agentPayload["data"] as? [String: Any]
        let runId = agentPayload["runId"] as? String

        await MainActor.run { [weak self] in
            guard let self else { return }

            // Track the session key from agent events
            if let agentSessionKey = agentPayload["sessionKey"] as? String,
               !agentSessionKey.contains("cron:") {
                self.sessionKey = agentSessionKey
            }

            switch stream {
            case "lifecycle":
                let phase = eventData?["phase"] as? String ?? ""
                if phase == "start" {
                    self.activeRunId = runId
                    self.liveText = ""
                    self.setActivity(.thinking)
                    // Fetch history to capture user messages from Dashboard/Feishu
                    // (gateway doesn't broadcast user messages as events)
                    if let ws = self.activeWs {
                        let sk = self.sessionKey
                        Task {
                            await self.fetchHistoryForSession(ws: ws, key: sk)
                        }
                    }
                } else if phase == "end" {
                    // Don't append liveText here — handleChatEvent "final" handles it
                    self.liveText = ""
                    self.activeRunId = nil
                    // Brief "done" flash then idle
                    self.setActivity(.done)
                    self.doneTimer?.cancel()
                    self.doneTimer = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        await MainActor.run { [weak self] in
                            if self?.activity == .done {
                                self?.setActivity(.idle)
                            }
                        }
                    }
                }

            case "assistant":
                // Agent streaming text delta
                if let delta = eventData?["delta"] as? String {
                    self.liveText += delta
                }
                if self.activity != .typing {
                    self.setActivity(.typing)
                }

            case "tool":
                // Tool invocation
                let toolName = (eventData?["name"] as? String ?? "").lowercased()
                if toolName.contains("search") || toolName.contains("browse") || toolName.contains("web") {
                    self.setActivity(.searching)
                } else {
                    self.setActivity(.toolUse)
                }

            case "error":
                self.setActivity(.error)
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run { [weak self] in
                        if self?.activity == .error {
                            self?.setActivity(.idle)
                        }
                    }
                }

            default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func appendMessage(role: LobsterRecentMessage.Role, content: String) {
        let msg = LobsterRecentMessage(role: role, content: content)
        recentMessages.append(msg)
        // Keep last 50 messages
        if recentMessages.count > Self.maxPersistedMessages {
            recentMessages.removeFirst(recentMessages.count - Self.maxPersistedMessages)
        }
        Self.saveMessages(recentMessages)
    }

    // MARK: - Persistence

    private static func saveMessages(_ messages: [LobsterRecentMessage]) {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }

    private static func loadMessages() -> [LobsterRecentMessage] {
        guard let data = UserDefaults.standard.data(forKey: messagesKey),
              let messages = try? JSONDecoder().decode([LobsterRecentMessage].self, from: data) else {
            return []
        }
        // Only keep last maxPersistedMessages
        if messages.count > maxPersistedMessages {
            return Array(messages.suffix(maxPersistedMessages))
        }
        return messages
    }

    /// Clear all message history
    func clearHistory() {
        recentMessages.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.messagesKey)
    }

    func setActivity(_ newActivity: LobsterActivity) {
        // When network is down, only allow setting to offline
        if !isNetworkAvailable && newActivity != .offline {
            return
        }
        activity = newActivity

        // Map detailed activity to simple 3-state mood for mini view
        let newMood: LobsterMood
        switch newActivity {
        case .idle, .done:
            newMood = .idle
        case .thinking, .typing, .toolUse, .searching, .error:
            newMood = .working
        case .offline:
            newMood = .offline
        }

        if mood != newMood {
            withAnimation(.easeInOut(duration: 0.3)) {
                mood = newMood
            }
        }
    }

    /// Send a message through the notch input via WebSocket (same channel as Dashboard)
    func sendFromNotch(_ text: String) {
        appendMessage(role: .user, content: text)

        guard let ws = activeWs else { return }

        let idempotencyKey = UUID().uuidString

        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": text,
                "deliver": false,
                "idempotencyKey": idempotencyKey
            ] as [String: Any]
        ]

        Task {
            do {
                let data = try JSONSerialization.data(withJSONObject: req)
                try await ws.send(.data(data))
            } catch {
                await MainActor.run { [weak self] in
                    self?.appendMessage(role: .assistant, content: "发送失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketTask helpers

private extension URLSessionWebSocketTask.Message {
    var data: Data? {
        switch self {
        case .data(let d): return d
        case .string(let s): return s.data(using: .utf8)
        @unknown default: return nil
        }
    }
}
