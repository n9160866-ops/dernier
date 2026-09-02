import SwiftUI

struct ChatView: View {
    let conversationId: Int
    let name: String
    let isGroup: Bool
    let peerUserId: Int

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var typingText = ""
    @State private var showMembers = false
    @State private var typingSentAt: Date = .distantPast
    @State private var typingClearTask: Task<Void, Never>?

    private let wsListener = WSListenerBox()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(messages) { message in
                            messageBubble(message).id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if !typingText.isEmpty {
                Text(typingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: inputText) { sendTypingIfNeeded() }
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(isGroup ? "👥 \(name)" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isGroup {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showMembers = true
                    } label: {
                        Image(systemName: "person.3")
                    }
                }
            }
        }
        .sheet(isPresented: $showMembers) {
            NavigationStack {
                GroupMembersView(conversationId: conversationId, groupName: name) { leftGroup in
                    showMembers = false
                    if leftGroup { dismiss() }
                }
            }
        }
        .task {
            wsListener.onMessage = { data in handleWSMessage(data) }
            WSManager.shared.addListener(wsListener)
            WSManager.shared.connect()
            AppState.shared.openConversationId = conversationId
            await loadMessages()
        }
        .onDisappear {
            WSManager.shared.removeListener(wsListener)
            if AppState.shared.openConversationId == conversationId {
                AppState.shared.openConversationId = -1
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMe = message.senderId == Session.userId
        HStack {
            if isMe { Spacer(minLength: 40) }
            Text(message.deleted ? "Message supprimé" : (message.content ?? ""))
                .italic(message.deleted)
                .foregroundStyle(message.deleted ? Color.secondary : (isMe ? Color.white : Color.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMe ? Color.accentColor : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if !isMe { Spacer(minLength: 40) }
        }
    }

    private func loadMessages() async {
        do {
            let body = try await APIClient.loadMessages(conversationId: conversationId)
            let list = body.map { m in
                ChatMessage(
                    id: m.int("id"),
                    conversationId: conversationId,
                    senderId: m.int("sender_id"),
                    content: m.isNull("content") ? nil : m.optString("content"),
                    deleted: m.bool("deleted"),
                    createdAt: m.int64("created_at", Int64(Date().timeIntervalSince1970 * 1000))
                )
            }
            await MainActor.run { self.messages = list }
        } catch {
            // Silencieux, comme côté Android (onError vide dans loadMessages)
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        WSManager.shared.sendMessage(conversationId: conversationId, text: text)
        inputText = ""
    }

    private func sendTypingIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(typingSentAt) > 1.5 {
            WSManager.shared.sendTyping(conversationId: conversationId, isTyping: true)
            typingSentAt = now
        }
    }

    private func showTyping(_ isTyping: Bool) {
        typingClearTask?.cancel()
        if isTyping {
            typingText = "\(name) est en train d'écrire..."
            typingClearTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run { typingText = "" }
                }
            }
        } else {
            typingText = ""
        }
    }

    // MARK: - Messages temps réel

    private func handleWSMessage(_ data: JSONDict) {
        switch data.string("type") {
        case "message":
            guard data.int("conversation_id") == conversationId else { return }
            let m = ChatMessage(
                id: data.int("id"),
                conversationId: conversationId,
                senderId: data.int("sender_id"),
                content: data.isNull("content") ? nil : data.optString("content"),
                deleted: false,
                createdAt: data.int64("created_at", Int64(Date().timeIntervalSince1970 * 1000))
            )
            messages.append(m)
        case "message_deleted":
            let mid = data.int("message_id")
            if let idx = messages.firstIndex(where: { $0.id == mid }) {
                messages[idx].deleted = true
            }
        case "typing":
            if data.int("conversation_id") == conversationId {
                showTyping(data.bool("is_typing"))
            }
        case "group_removed":
            // On vient de nous retirer de ce groupe : on ferme l'écran.
            if data.int("conversation_id") == conversationId {
                dismiss()
            }
        default:
            break
        }
    }
}
