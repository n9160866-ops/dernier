import SwiftUI

/// Écran principal : liste des amis (chats privés) + groupes.
/// Équivalent de ConversationsActivity.kt.
struct ConversationsView: View {
    @Binding var isLoggedIn: Bool

    @State private var items: [ConversationItem] = []
    @State private var knownUsernames: [String] = []
    @State private var isLoading = false
    @State private var errorText = ""
    @State private var showNewGroup = false
    @State private var showFriends = false
    @State private var showAdmin = false

    @State private var openChatConversationId: Int?
    @State private var openChatName = ""
    @State private var openChatIsGroup = false
    @State private var openChatPeerId = -1
    @State private var navigateToChat = false

    private let wsListener = WSListenerBox()

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button {
                        onItemClick(item)
                    } label: {
                        HStack {
                            if !item.isGroup {
                                Circle()
                                    .fill(item.isOnline ? Color.green : Color.gray)
                                    .frame(width: 10, height: 10)
                            }
                            Text(item.isGroup ? "👥 \(item.name)" : item.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if item.unread > 0 {
                                Text("\(item.unread)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Circle().fill(Color.red))
                            }
                        }
                    }
                }
            }
            .refreshable { await loadAllAsync() }
            .navigationTitle(Session.username ?? "")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Déconnexion", role: .destructive) { logout() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if Session.role == "admin" {
                        Button { showAdmin = true } label: { Image(systemName: "shield") }
                    }
                    Button { showFriends = true } label: { Image(systemName: "person.2") }
                    Button { showNewGroup = true } label: { Image(systemName: "plus.bubble") }
                }
            }
            .alert("Erreur", isPresented: .constant(!errorText.isEmpty), actions: {
                Button("OK") { errorText = "" }
            }, message: { Text(errorText) })
            .sheet(isPresented: $showFriends) {
                NavigationStack { FriendsView() }
            }
            .sheet(isPresented: $showAdmin) {
                NavigationStack { AdminView() }
            }
            .sheet(isPresented: $showNewGroup) {
                NewGroupSheet(knownUsernames: knownUsernames) { name, conversationId in
                    showNewGroup = false
                    Task { await loadAllAsync() }
                    openChatConversationId = conversationId
                    openChatName = name
                    openChatIsGroup = true
                    openChatPeerId = -1
                    navigateToChat = true
                }
            }
            .navigationDestination(isPresented: $navigateToChat) {
                if let cid = openChatConversationId {
                    ChatView(conversationId: cid, name: openChatName, isGroup: openChatIsGroup, peerUserId: openChatPeerId)
                }
            }
        }
        .task {
            wsListener.onMessage = { data in handleWSMessage(data) }
            WSManager.shared.addListener(wsListener)
            WSManager.shared.connect()
            AppState.shared.openConversationId = -1
            await loadAllAsync()
        }
        .onDisappear {
            WSManager.shared.removeListener(wsListener)
        }
    }

    private func onItemClick(_ item: ConversationItem) {
        if item.isGroup {
            openChatConversationId = item.conversationId
            openChatName = item.name
            openChatIsGroup = true
            openChatPeerId = -1
            navigateToChat = true
        } else {
            Task {
                do {
                    let body = try await APIClient.openPrivateConversation(username: item.name)
                    await MainActor.run {
                        openChatConversationId = body.int("conversation_id")
                        openChatName = item.name
                        openChatIsGroup = false
                        openChatPeerId = item.id
                        navigateToChat = true
                    }
                } catch {
                    await MainActor.run { errorText = error.localizedDescription }
                }
            }
        }
    }

    // 🤝 On ne peut démarrer une discussion ou un appel qu'avec ses amis :
    // on liste les amis (pas tous les utilisateurs) comme contacts possibles.
    private func loadAllAsync() async {
        isLoading = true
        var combined: [ConversationItem] = []
        do {
            let friends = try await APIClient.listFriends()
            var names: [String] = []
            for f in friends {
                guard let u = f.dict("user") else { continue }
                names.append(u.string("username"))
                combined.append(ConversationItem(
                    isGroup: false,
                    id: u.int("id"),
                    conversationId: nil,
                    name: u.string("username"),
                    isOnline: u.int("is_online") == 1
                ))
            }
            knownUsernames = names
        } catch {
            await MainActor.run { isLoading = false; errorText = error.localizedDescription }
            return
        }

        do {
            let conversations = try await APIClient.listConversations()
            for c in conversations where c.int("is_group") == 1 {
                combined.append(ConversationItem(
                    isGroup: true,
                    id: c.int("id"),
                    conversationId: c.int("id"),
                    name: c.string("name", "Groupe")
                ))
            }
        } catch {
            // silencieux, comme côté Android : on garde au moins les amis
        }

        await MainActor.run {
            isLoading = false
            items = combined
        }
    }

    private func logout() {
        WSManager.shared.disconnect()
        Session.clear()
        isLoggedIn = false
    }

    // ----- présence + badges non-lus en temps réel -----
    private func handleWSMessage(_ data: JSONDict) {
        switch data.string("type") {
        case "presence":
            let uid = data.int("user_id")
            let online = data.bool("is_online")
            if let idx = items.firstIndex(where: { !$0.isGroup && $0.id == uid }) {
                items[idx].isOnline = online
            }
        case "message":
            let senderId = data.int("sender_id")
            if senderId != Session.userId {
                let cid = data.int("conversation_id")
                if let idx = items.firstIndex(where: { $0.conversationId == cid || ($0.isGroup && $0.id == cid) }) {
                    items[idx].unread += 1
                }
            }
        case "group_updated":
            Task { await loadAllAsync() }
        default:
            break
        }
    }
}

/// Petite feuille modale pour créer un groupe (nom + sélection d'amis),
/// équivalent du AlertDialog construit dynamiquement dans
/// ConversationsActivity.showNewGroupDialog().
private struct NewGroupSheet: View {
    let knownUsernames: [String]
    let onCreated: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom du groupe") {
                    TextField("Nom du groupe", text: $name)
                }
                Section("Membres") {
                    ForEach(knownUsernames, id: \.self) { uname in
                        Button {
                            if selected.contains(uname) { selected.remove(uname) } else { selected.insert(uname) }
                        } label: {
                            HStack {
                                Text(uname).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(uname) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                if !errorText.isEmpty {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nouveau groupe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") { create() } }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selected.isEmpty else {
            errorText = "Donne un nom et sélectionne au moins un membre."
            return
        }
        Task {
            do {
                let body = try await APIClient.createGroup(name: trimmed, usernames: Array(selected))
                await MainActor.run { onCreated(trimmed, body.int("conversation_id")) }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}
