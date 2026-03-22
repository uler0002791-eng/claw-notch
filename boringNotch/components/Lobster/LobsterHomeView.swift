//
//  LobsterHomeView.swift
//  boringNotch
//
//  Main lobster view when the notch is expanded.
//  Left: large status icon | Right: recent messages + input + dashboard button
//

import SwiftUI

struct LobsterHomeView: View {
    @ObservedObject var lobster = LobsterStateManager.shared
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Left: Status icon
            LobsterStatusView()
                .frame(width: 90)
                .padding(.leading, 4)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 8)

            // Right: Messages + Input
            VStack(spacing: 0) {
                messageList
                Divider().background(Color.white.opacity(0.08))
                inputArea
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: Notification.Name("lobsterTabDidActivate"), object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: Notification.Name("lobsterTabDidDeactivate"), object: nil)
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if lobster.recentMessages.isEmpty && lobster.liveText.isEmpty {
                        emptyState
                    }

                    // Show last 5 messages
                    ForEach(lobster.recentMessages.suffix(5)) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }

                    // Live streaming text
                    if !lobster.liveText.isEmpty && lobster.activity == .typing {
                        liveBubble
                            .id("live")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: lobster.recentMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lobster.recentMessages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: lobster.liveText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Text("🦞")
                    .font(.system(size: 20))
                Text("等待消息...")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }

    private var liveBubble: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("🦞")
                .font(.system(size: 10))

            Text(truncate(lobster.liveText, limit: 100))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 20)
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 6) {
            TextField("发消息...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(canSend ? .orange : .gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            // Clear history button
            Button(action: { lobster.clearHistory() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(lobster.recentMessages.isEmpty)
            .help("清除聊天记录")

            // Open Dashboard button
            Button(action: openDashboard) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("打开 Dashboard")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        lobster.sendFromNotch(text)
    }

    private func openDashboard() {
        NSWorkspace.shared.open(lobster.dashboardURL)
    }

    // MARK: - Helpers

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "..."
    }
}

// MARK: - Message Row (chat bubble)

private struct MessageRow: View {
    let message: LobsterRecentMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if isUser {
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(truncated)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .lineLimit(5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(timeString)
                        .font(.system(size: 7))
                        .foregroundColor(.gray.opacity(0.5))
                }
            } else {
                Text("🦞")
                    .font(.system(size: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(truncated)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(timeString)
                        .font(.system(size: 7))
                        .foregroundColor(.gray.opacity(0.5))
                }
                Spacer(minLength: 20)
            }
        }
    }

    private var truncated: String {
        if message.content.count <= 100 { return message.content }
        return String(message.content.prefix(100)) + "..."
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: message.timestamp)
    }
}

#Preview {
    ZStack {
        Color.black
        LobsterHomeView()
            .frame(width: 560, height: 160)
    }
}
