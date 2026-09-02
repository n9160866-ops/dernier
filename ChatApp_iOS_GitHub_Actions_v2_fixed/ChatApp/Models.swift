import Foundation

/// Une entrée dans la liste de gauche : soit un utilisateur (chat privé), soit un groupe.
struct ConversationItem: Identifiable, Equatable {
    var isGroup: Bool
    var id: Int                 // user_id si privé, conversation_id si groupe
    var conversationId: Int?    // connu seulement une fois la conversation privée ouverte, ou pour un groupe
    var name: String
    var isOnline: Bool = false
    var unread: Int = 0
}

struct ChatMessage: Identifiable, Equatable {
    var id: Int
    var conversationId: Int
    var senderId: Int
    var content: String?
    var deleted: Bool
    var createdAt: Int64
}
