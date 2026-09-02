import Foundation

/// État global léger, partagé entre les vues et l'AppDelegate, pour éviter
/// d'afficher une notification pour une conversation déjà à l'écran.
/// Équivalent de AppState.kt.
final class AppState {
    static let shared = AppState()
    private init() {}

    var isAppInForeground: Bool = true

    /// id de la conversation actuellement ouverte dans ChatView, -1 si aucune.
    var openConversationId: Int = -1
}
