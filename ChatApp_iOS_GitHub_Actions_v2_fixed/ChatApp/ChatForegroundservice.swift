import Foundation

/// Équivalent du cache de noms tenu par ChatForegroundService.kt
/// (usernamesById / groupNamesById), utilisé pour donner un titre lisible
/// aux notifications de nouveaux messages.
///
/// ⚠️ Ce fichier ne fait QUE la partie "résolution de noms" qui manquait
/// côté Swift. Il ne recrée pas de vrai service premier-plan : comme
/// expliqué dans NotificationHelper.swift, iOS n'autorise pas de
/// WebSocket permanente en arrière-plan sans un vrai serveur push APNs.
/// Cette classe reste donc utile uniquement tant que l'app est encore
/// active (arrière-plan récent) et que WSManager.shared est connecté —
/// exactement le même périmètre que le AppDelegate.handleGlobalMessage
/// déjà présent dans ChatApp.swift.
///
/// Utilisation : appeler `ChatNameCache.shared.refresh()` après le login
/// (comme `refreshNameCaches()` dans onCreate côté Android), puis, dans
/// le handler WebSocket global, remplacer le texte codé en dur
/// "Nouveau message" par `ChatNameCache.shared.title(for: data)` afin
/// d'obtenir un titre équivalent à celui du service Android
/// ("NomDuGroupe • pseudo" pour un groupe, ou juste le pseudo en privé).
final class ChatNameCache {
    static let shared = ChatNameCache()
    private init() {}

    private var usernamesById: [Int: String] = [:]
    private var groupNamesById: [Int: String] = [:]

    /// Recharge les deux caches depuis le serveur.
    /// Équivalent de ChatForegroundService.refreshNameCaches().
    func refresh() {
        Task {
            if let users = try? await APIClient.listUsers() {
                var map: [Int: String] = [:]
                for u in users {
                    map[u.int("id")] = u.string("username")
                }
                usernamesById = map
            }
            if let conversations = try? await APIClient.listConversations() {
                var map: [Int: String] = [:]
                for c in conversations where c.int("is_group") == 1 {
                    map[c.int("id")] = c.string("name", "Groupe")
                }
                groupNamesById = map
            }
        }
    }

    /// true si conversationId correspond à un groupe connu.
    func isGroup(conversationId: Int) -> Bool {
        groupNamesById[conversationId] != nil
    }

    /// Construit le titre de notification à partir d'un message WebSocket
    /// brut de type "message", comme handleIncomingMessage côté Android :
    /// "NomDuGroupe • pseudo" pour un groupe, sinon juste le pseudo.
    /// Retourne nil si le message vient de l'utilisateur courant (rien à notifier).
    func title(for data: JSONDict) -> String? {
        let senderId = data.int("sender_id")
        guard senderId != Session.userId else { return nil }

        let conversationId = data.int("conversation_id")
        let senderName = usernamesById[senderId] ?? "Nouveau message"

        if let groupName = groupNamesById[conversationId] {
            return "\(groupName) • \(senderName)"
        }
        return senderName
    }
}
