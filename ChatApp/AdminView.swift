import SwiftUI

/// Panneau d'administration : liste des utilisateurs, promotion/rétrogradation
/// admin, suppression de compte. Équivalent de AdminActivity.kt.
struct AdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var users: [JSONDict] = []
    @State private var errorText = ""

    var body: some View {
        List {
            ForEach(users.indices, id: \.self) { idx in
                let u = users[idx]
                let id = u.int("id")
                let role = u.string("role", "user")
                HStack {
                    VStack(alignment: .leading) {
                        Text(u.string("username"))
                        Text(role).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role == "admin" ? "Rétrograder" : "Promouvoir") {
                        setRole(id: id, newRole: role == "admin" ? "user" : "admin")
                    }
                    .buttonStyle(.bordered)
                    Button("Supprimer", role: .destructive) { delete(id: id) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Administration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
        }
        .alert("Erreur", isPresented: .constant(!errorText.isEmpty), actions: {
            Button("OK") { errorText = "" }
        }, message: { Text(errorText) })
        .task { await load() }
    }

    private func load() async {
        do {
            users = try await APIClient.adminListUsers()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setRole(id: Int, newRole: String) {
        Task {
            do {
                _ = try await APIClient.adminSetRole(userId: id, role: newRole)
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }

    private func delete(id: Int) {
        Task {
            do {
                _ = try await APIClient.adminDeleteUser(userId: id)
                await load()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}
