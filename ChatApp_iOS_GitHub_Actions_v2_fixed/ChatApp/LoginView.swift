import SwiftUI

/// Écran de connexion / inscription. Équivalent de LoginActivity.kt.
struct LoginView: View {
    @Binding var isLoggedIn: Bool

    @State private var username = ""
    @State private var password = ""
    @State private var errorText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("ChatApp").font(.largeTitle.bold())

            TextField("Pseudo", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Mot de passe", text: $password)
                .textFieldStyle(.roundedBorder)

            if !errorText.isEmpty {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }

            if isLoading {
                ProgressView()
            }

            HStack(spacing: 12) {
                Button("Se connecter") { submit(register: false) }
                    .buttonStyle(.borderedProminent)
                Button("Créer un compte") { submit(register: true) }
                    .buttonStyle(.bordered)
            }
            .disabled(isLoading)

            Spacer()
        }
        .padding()
        .onAppear {
            // Reprise de session automatique si déjà connecté
            if Session.isLoggedIn() {
                isLoggedIn = true
            }
        }
    }

    private func submit(register: Bool) {
        let uname = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pwd = password
        guard !uname.isEmpty, !pwd.isEmpty else {
            errorText = "Remplis les deux champs."
            return
        }
        errorText = ""
        isLoading = true
        Task {
            do {
                let body = register
                    ? try await APIClient.register(username: uname, password: pwd)
                    : try await APIClient.login(username: uname, password: pwd)
                await MainActor.run {
                    isLoading = false
                    let user = body.dict("user") ?? [:]
                    Session.token = body.optString("token")
                    Session.userId = user.int("id", -1)
                    Session.username = user.optString("username")
                    Session.role = user.string("role", "user")
                    isLoggedIn = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
