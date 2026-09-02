import SwiftUI

/// Écran "Amis" : trois onglets (amis confirmés / demandes reçues / demandes
/// envoyées), plus un champ pour envoyer une nouvelle demande par pseudo.
/// Equivalent de FriendsActivity.kt.
struct FriendsView: View {
    enum Tab: String, CaseIterable {
        case friends = "Amis"
        case received = "Reçues"
        case sent = "Envoyées"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var currentTab: Tab = .friends
    @State private var items: [JSONDict] = []
    @State private var isLoading = false
    @State private var errorText = ""
    @State private var addUsername = ""

    @State private var openChatConversationId: Int?
    @State private var openChatName = ""
    @State private var openChatPeerId = -1
    @State private var navigateToChat = false

    private let wsListener = WSListenerBox()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Ajouter un ami par pseudo", text: $addUsername)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                Button("Ajouter") { addFriend() }
                    .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Picker("Onglet", selection: $currentTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: currentTab) { Task { await load() } }

            if items.isEmpty && !isLoading {
                Spacer()
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(items.indices, id: \.self) { idx in
                        friendRow(items[idx])
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Amis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
            }
        }
        .alert("Erreur", isPresented: .constant(!errorText.isEmpty), actions: {
            Button("OK") { errorText = "" }
        }, message: { Text(errorText) })
        .navigationDestination(isPresented: $navigateToChat) {
            if let cid = openChatConversationId {
                ChatView(conversationId: cid, name: openChatName, isGroup: false, peerUserId: openChatPeerId)
            }
        }
        .task {
            wsListener.onMessage = { data in handleWSMessage(data) }
            WSManager.shared.addListener(wsListener)
            await load()
        }
        .onDisappear {
            WSManager.shared.removeListener(wsListener)
        }
    }

    private var emptyMessage: String {
        switch currentTab {
        case .friends: return "Aucun ami pour l'instant."
        case .received: return "Aucune demande reçue."
        case .sent: return "Aucune demande envoyée."
        }
    }

    @ViewBuilder
    private func friendRow(_ item: JSONDict) -> some View {
        let user = item.dict("user") ?? [:]
        let friendshipId = item.int("id")
        let uname = user.string("username", "?")
        let online = user.bool("is_online")

        HStack {
            if currentTab == .friends {
                Circle().fill(online ? Color.green : Color.gray).frame(width: 10, height: 10)
            }
            Text(uname)
            Spacer()
            switch currentTab {
            case .friends:
                Button("Message") { openChat(username: uname, userId: user.int("id")) }
                Button(role: .destructive) { removeFriendship(friendshipId) } label: { Text("Retirer") }
            case .received:
                Button("Accepter") { accept(friendshipId) }
                Button(role: .destructive) { removeFriendship(friendshipId) } label: { Text("Refuser") }
            case .sent:
                Button(role: .destructive) { removeFriendship(friendshipId) } label: { Text("Annuler") }
            }
        }
        .buttonStyle(.borderless)
    }

    private func load() async {
        isLoading = true
        do {
            let list: [JSONDict]
            switch currentTab {
            case .friends: list = try await APIClient.listFriends()
            case .received: list = try await APIClient.listPendingFriendRequests()
            case .sent: list = try await APIClient.listSentFriendRequests()
            }
            await MainActor.run { self.items = list; self.isLoading = false }
        } catch {
            await MainActor.run { self.isLoading = false; self.errorText = error.localizedDescription }
        }
    }

    private func addFriend() {
        let uname = addUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uname.isEmpty else { return }
        Task {
            do {
                _ = try await APIClient.sendFriendRequest(username: uname)
                await MainActor.run { addUsername = "" }
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func accept(_ friendshipId: Int) {
        Task {
            do {
                _ = try await APIClient.acceptFriendRequest(friendshipId: friendshipId)
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func removeFriendship(_ friendshipId: Int) {
        Task {
            do {
                _ = try await APIClient.removeFriendship(friendshipId: friendshipId)
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func openChat(username: String, userId: Int) {
        Task {
            do {
                let body = try await APIClient.openPrivateConversation(username: username)
                await MainActor.run {
                    openChatConversationId = body.int("conversation_id")
                    openChatName = username
                    openChatPeerId = userId
                    navigateToChat = true
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func handleWSMessage(_ data: JSONDict) {
        switch data.string("type") {
        case "friend_request", "friend_accepted", "friend_declined", "friend_removed":
            Task { await load() }
        case "presence":
            let uid = data.int("user_id")
            let online = data.bool("is_online")
            if let idx = items.firstIndex(where: { ($0.dict("user")?.int("id")) == uid }) {
                var user = items[idx].dict("user") ?? [:]
                user["is_online"] = online
                items[idx]["user"] = user
            }
        default:
            break
        }
    }
}
