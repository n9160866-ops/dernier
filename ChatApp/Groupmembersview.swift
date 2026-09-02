import SwiftUI

/// 👥 Gestion des membres d'un groupe.
///
/// Règle (identique côté serveur — voir server.js `isGroupAdmin`, et déjà
/// appliquée côté site web et côté Android) :
///   - Tout membre du groupe peut VOIR la liste des membres.
///   - Seuls le PROPRIÉTAIRE et les membres qu'il a désignés comme ADMINS
///     peuvent ajouter ou retirer des membres.
///   - Seul le PROPRIÉTAIRE peut promouvoir/rétrograder des admins.
///   - Le propriétaire ne peut pas être retiré du groupe.
///
/// Cette vue ne fait qu'AFFICHER/MASQUER les actions selon ce rôle — la
/// vérification qui compte reste côté serveur (toutes les routes
/// /api/conversations/:id/members et /admins la refont), donc même un
/// client modifié ne peut pas contourner la règle.
///
/// `onDone(leftGroup:)` est appelé quand la feuille doit se fermer ;
/// `leftGroup == true` signifie que ChatView doit aussi se fermer, comme
/// `setResult(RESULT_OK, ...)` côté Android.
struct GroupMembersView: View {
    let conversationId: Int
    let groupName: String
    let onDone: (Bool) -> Void

    @State private var ownerId = -1
    @State private var adminIds: Set<Int> = []
    @State private var members: [JSONDict] = []
    @State private var friendUsernames: [String] = []
    @State private var errorText = ""
    @State private var showAddMember = false

    private var isOwner: Bool { ownerId == Session.userId }
    private var isAdmin: Bool { isOwner || adminIds.contains(Session.userId) }

    var body: some View {
        List {
            if !isAdmin {
                Section {
                    Text("Seuls le propriétaire et les admins peuvent gérer les membres.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(members.indices, id: \.self) { idx in
                memberRow(members[idx])
            }
        }
        .navigationTitle("👥 \(groupName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { onDone(false) } }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isAdmin {
                    Button { showAddMember = true } label: { Image(systemName: "person.badge.plus") }
                }
                Button("Quitter", role: .destructive) { confirmLeave = true }
            }
        }
        .alert("Erreur", isPresented: .constant(!errorText.isEmpty), actions: {
            Button("OK") { errorText = "" }
        }, message: { Text(errorText) })
        .alert("Quitter le groupe", isPresented: $confirmLeave, actions: {
            Button("Quitter", role: .destructive) { removeMember(userId: Session.userId, isSelf: true) }
            Button("Annuler", role: .cancel) {}
        }, message: { Text("Tu ne recevras plus les messages de \"\(groupName)\".") })
        .sheet(isPresented: $showAddMember) {
            AddMemberSheet(
                candidates: friendUsernames.filter { uname in members.allSatisfy { $0.string("username") != uname } },
                onAdd: { selected in
                    showAddMember = false
                    for uname in selected { addMember(uname) }
                }
            )
        }
        .task { await load() }
    }

    @State private var confirmLeave = false

    @ViewBuilder
    private func memberRow(_ m: JSONDict) -> some View {
        let id = m.int("id")
        let uname = m.string("username")
        let memberIsOwner = id == ownerId
        let memberIsAdmin = adminIds.contains(id)
        let memberIsSelf = id == Session.userId

        HStack {
            VStack(alignment: .leading) {
                Text(memberIsSelf ? "\(uname) (toi)" : uname)
                if memberIsOwner {
                    Text("👑 Propriétaire").font(.caption).foregroundStyle(.secondary)
                } else if memberIsAdmin {
                    Text("🛠️ Admin").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // 👑 Promouvoir/rétrograder : réservé au propriétaire, jamais sur lui-même
            if isOwner && !memberIsOwner {
                Button(memberIsAdmin ? "Rétrograder" : "Promouvoir") { toggleAdmin(userId: id, currentlyAdmin: memberIsAdmin) }
                    .buttonStyle(.bordered)
            }
            // 🚪 Retirer quelqu'un d'autre : propriétaire/admins uniquement,
            // jamais le propriétaire, jamais soi-même (utiliser "Quitter le groupe")
            if isAdmin && !memberIsOwner && !memberIsSelf {
                Button("Retirer", role: .destructive) { removeMember(userId: id, isSelf: false) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func load() async {
        // 🤝 On a besoin de la liste d'amis pour ne proposer, à l'ajout,
        // que des personnes avec qui on est ami (le serveur le vérifie de
        // toute façon, mais autant ne pas proposer un choix qui échouera).
        do {
            let friends = try await APIClient.listFriends()
            friendUsernames = friends.compactMap { $0.dict("user")?.string("username") }
        } catch {
            friendUsernames = []
        }
        await loadConversation()
    }

    private func loadConversation() async {
        do {
            let conversations = try await APIClient.listConversations()
            guard let found = conversations.first(where: { $0.int("is_group") == 1 && $0.int("id") == conversationId }) else {
                await MainActor.run { errorText = "Groupe introuvable" }
                return
            }
            let owner = found.int("owner_id", -1)
            let admins = Set(found.intArray("admin_ids"))
            var mem: [JSONDict] = found.array("members")
            if mem.isEmpty {
                mem = found.intArray("member_ids").map { ["id": $0, "username": "#\($0)"] }
            }
            mem.sort { a, b in
                let aOwner = a.int("id") == owner
                let bOwner = b.int("id") == owner
                if aOwner != bOwner { return aOwner }
                return a.string("username") < b.string("username")
            }
            await MainActor.run {
                ownerId = owner
                adminIds = admins
                members = mem
            }
        } catch {
            await MainActor.run { errorText = error.localizedDescription }
        }
    }

    private func addMember(_ uname: String) {
        Task {
            do {
                _ = try await APIClient.addGroupMember(conversationId: conversationId, username: uname)
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func removeMember(userId: Int, isSelf: Bool) {
        Task {
            do {
                _ = try await APIClient.removeGroupMember(conversationId: conversationId, userId: userId)
                if isSelf {
                    await MainActor.run { onDone(true) }
                } else {
                    await load()
                }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func toggleAdmin(userId: Int, currentlyAdmin: Bool) {
        Task {
            do {
                if currentlyAdmin {
                    _ = try await APIClient.demoteGroupAdmin(conversationId: conversationId, userId: userId)
                } else {
                    _ = try await APIClient.promoteGroupAdmin(conversationId: conversationId, userId: userId)
                }
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}

private struct AddMemberSheet: View {
    let candidates: [String]
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    Text("Tous tes amis sont déjà dans le groupe.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(candidates, id: \.self) { uname in
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
            }
            .navigationTitle("Ajouter des membres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { onAdd(Array(selected)) }.disabled(selected.isEmpty)
                }
            }
        }
    }
}
