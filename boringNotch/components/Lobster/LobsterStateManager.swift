//
//  LobsterStateManager.swift
//  boringNotch
//
//  Manages lobster animation states via WebSocket connection to OpenClaw gateway.
//  Listens for real-time agent events to drive lobster mood and collect messages.
//

import Combine
import SwiftUI

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

    /// Recent messages collected from WebSocket agent events (last 50, persisted)
    @Published var recentMessages: [LobsterRecentMessage] = []

    private static let messagesKey = "lobsterRecentMessages"
    private static let maxPersistedMessages = 50

    /// Current streaming text being assembled from assistant deltas
    @Published var liveText: String = ""

    /// Current run ID being tracked
    private var activeRunId: String?

    private var wsTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    private var doneTimer: Task<Void, Never>?

    /// Active WebSocket handle for sending messages
    private var activeWs: URLSessionWebSocketTask?

    private let gatewayHost: String
    private let gatewayPort: Int
    private let gatewayToken: String

    private init() {
        self.gatewayHost = UserDefaults.standard.string(forKey: "openClawHost") ?? "127.0.0.1"
        let port = UserDefaults.standard.integer(forKey: "openClawPort")
        self.gatewayPort = port == 0 ? 18789 : port
        self.gatewayToken = UserDefaults.standard.string(forKey: "openClawToken") ?? "558f111a274fc00270ebf0e6ae6e36133620fb40a7f57e2d"
        self.recentMessages = Self.loadMessages()
        startWebSocket()
    }

    var dashboardURL: URL {
        URL(string: "http://\(gatewayHost):\(gatewayPort)")!
    }

    // MARK: - WebSocket Connection

    private func startWebSocket() {
        wsTask?.cancel()
        wsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.connectAndListen()
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

            // Step 2: Send connect
            let connectParams: [String: Any] = [
                "type": "req",
                "id": UUID().uuidString,
                "method": "connect",
                "params": [
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": [
                        "id": "gateway-client",
                        "version": "1.0",
                        "platform": "macos",
                        "mode": "webchat"
                    ],
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
                  let hello = try? JSONSerialization.jsonObject(with: helloData) as? [String: Any],
                  hello["ok"] as? Bool == true else {
                wsTaskHandle.cancel(with: .internalServerError, reason: nil)
                return
            }

            // Connected
            reconnectDelay = 1.0
            await MainActor.run { [weak self] in
                self?.activeWs = wsTaskHandle
                self?.setActivity(.idle)
            }

            // Step 4: Listen for events
            while !Task.isCancelled {
                let message = try await wsTaskHandle.receive()
                guard let data = message.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                let event = json["event"] as? String ?? ""
                if event == "agent" {
                    await handleAgentEvent(json)
                }
            }

        } catch {
            wsTaskHandle.cancel(with: .goingAway, reason: nil)
            await MainActor.run { [weak self] in
                self?.activeWs = nil
            }
        }
    }

    // MARK: - Agent Event Handling

    private func handleAgentEvent(_ json: [String: Any]) async {
        guard let agentPayload = json["payload"] as? [String: Any],
              let stream = agentPayload["stream"] as? String,
              let eventData = agentPayload["data"] as? [String: Any] else { return }

        let runId = agentPayload["runId"] as? String

        await MainActor.run { [weak self] in
            guard let self else { return }

            switch stream {
            case "lifecycle":
                let phase = eventData["phase"] as? String ?? ""
                if phase == "start" {
                    self.activeRunId = runId
                    self.liveText = ""
                    self.setActivity(.thinking)
                } else if phase == "end" {
                    // Finalize any accumulated live text as a message
                    if !self.liveText.isEmpty {
                        self.appendMessage(role: .assistant, content: self.liveText)
                        self.liveText = ""
                    }
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
                // Streaming text delta
                if let delta = eventData["delta"] as? String {
                    self.liveText += delta
                }
                if self.activity != .typing {
                    self.setActivity(.typing)
                }

            case "tool":
                // Tool invocation
                let toolName = (eventData["name"] as? String ?? "").lowercased()
                if toolName.contains("search") || toolName.contains("browse") || toolName.contains("web") {
                    self.setActivity(.searching)
                } else {
                    self.setActivity(.toolUse)
                }

            case "user":
                // User message coming through (from Feishu / Discord / etc.)
                if let text = eventData["text"] as? String ?? eventData["content"] as? String {
                    self.appendMessage(role: .user, content: text)
                }

            case "error":
                self.setActivity(.error)
                // Auto-recover after 3 seconds
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

        let req: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.send",
            "params": [
                "sessionKey": "agent:main:main",
                "message": text,
                "deliver": false,
                "idempotencyKey": UUID().uuidString
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
