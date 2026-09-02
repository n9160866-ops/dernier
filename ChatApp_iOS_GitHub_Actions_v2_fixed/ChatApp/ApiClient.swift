import Foundation

enum APIError: LocalizedError {
    case connection(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connection(let msg): return "Connexion impossible : \(msg)"
        case .server(let msg): return msg
        case .invalidResponse: return "Réponse invalide du serveur"
        }
    }
}

/// Petit client HTTP au-dessus d'URLSession pour parler au serveur de chat
/// (routes /api/... définies dans server.js). Équivalent de ApiClient.kt,
/// mais en async/await plutôt qu'en callbacks.
enum APIClient {

    private static let session = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return config
    }())

    // MARK: - Bas niveau

    private static func request(_ path: String, method: String, body: JSONDict? = nil, auth: Bool) -> URLRequest {
        var req = URLRequest(url: URL(string: Config.baseURL + path)!)
        req.httpMethod = method
        if let body = body {
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if auth, let token = Session.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private static func sendDict(_ req: URLRequest) async throws -> JSONDict {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.connection(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        let obj = (try? JSONParsing.dict(from: data)) ?? [:]
        guard let http = http, (200...299).contains(http.statusCode) else {
            throw APIError.server(obj.string("error", "Erreur serveur"))
        }
        return obj
    }

    private static func sendArray(_ req: URLRequest) async throws -> [JSONDict] {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.connection(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        guard let http = http, (200...299).contains(http.statusCode) else {
            let obj = (try? JSONParsing.dict(from: data)) ?? [:]
            throw APIError.server(obj.string("error", "Erreur serveur"))
        }
        guard let arr = try? JSONParsing.array(from: data) else {
            throw APIError.invalidResponse
        }
        return arr
    }

    private static func post(_ path: String, _ body: JSONDict, auth: Bool) async throws -> JSONDict {
        try await sendDict(request(path, method: "POST", body: body, auth: auth))
    }

    private static func delete(_ path: String, auth: Bool = true) async throws -> JSONDict {
        try await sendDict(request(path, method: "DELETE", auth: auth))
    }

    private static func getDict(_ path: String) async throws -> JSONDict {
        try await sendDict(request(path, method: "GET", auth: true))
    }

    private static func getArray(_ path: String) async throws -> [JSONDict] {
        try await sendArray(request(path, method: "GET", auth: true))
    }

    // MARK: - Auth

    static func register(username: String, password: String) async throws -> JSONDict {
        try await post("/api/register", ["username": username, "password": password], auth: false)
    }

    static func login(username: String, password: String) async throws -> JSONDict {
        try await post("/api/login", ["username": username, "password": password], auth: false)
    }

    // MARK: - Conversations

    static func listUsers() async throws -> [JSONDict] {
        try await getArray("/api/users")
    }

    static func listConversations() async throws -> [JSONDict] {
        try await getArray("/api/conversations")
    }

    static func openPrivateConversation(username: String) async throws -> JSONDict {
        try await post("/api/conversations/private", ["username": username], auth: true)
    }

    static func createGroup(name: String, usernames: [String]) async throws -> JSONDict {
        try await post("/api/conversations/group", ["name": name, "usernames": usernames], auth: true)
    }

    static func addGroupMember(conversationId: Int, username: String) async throws -> JSONDict {
        try await post("/api/conversations/\(conversationId)/members", ["username": username], auth: true)
    }

    // 🚪 Retirer un membre du groupe (ou quitter soi-même : userId == Session.userId).
    // 👑 Le serveur vérifie que seuls le propriétaire/les admins peuvent retirer
    // quelqu'un d'autre — on ne fait ici que relayer l'appel.
    static func removeGroupMember(conversationId: Int, userId: Int) async throws -> JSONDict {
        try await delete("/api/conversations/\(conversationId)/members/\(userId)")
    }

    // 👑 Promouvoir/rétrograder un membre en admin du groupe — réservé au
    // propriétaire côté serveur.
    static func promoteGroupAdmin(conversationId: Int, userId: Int) async throws -> JSONDict {
        try await post("/api/conversations/\(conversationId)/admins/\(userId)", [:], auth: true)
    }

    static func demoteGroupAdmin(conversationId: Int, userId: Int) async throws -> JSONDict {
        try await delete("/api/conversations/\(conversationId)/admins/\(userId)")
    }

    static func loadMessages(conversationId: Int) async throws -> [JSONDict] {
        try await getArray("/api/conversations/\(conversationId)/messages")
    }

    // MARK: - Amis

    static func sendFriendRequest(username: String) async throws -> JSONDict {
        try await post("/api/friends/request", ["username": username], auth: true)
    }

    static func acceptFriendRequest(friendshipId: Int) async throws -> JSONDict {
        try await post("/api/friends/\(friendshipId)/accept", [:], auth: true)
    }

    static func removeFriendship(friendshipId: Int) async throws -> JSONDict {
        try await delete("/api/friends/\(friendshipId)")
    }

    static func listFriends() async throws -> [JSONDict] {
        try await getArray("/api/friends")
    }

    static func listPendingFriendRequests() async throws -> [JSONDict] {
        try await getArray("/api/friends/pending")
    }

    static func listSentFriendRequests() async throws -> [JSONDict] {
        try await getArray("/api/friends/sent")
    }

    // MARK: - Admin

    static func adminListUsers() async throws -> [JSONDict] {
        try await getArray("/api/admin/users")
    }

    static func adminDeleteUser(userId: Int) async throws -> JSONDict {
        try await delete("/api/admin/users/\(userId)")
    }

    static func adminSetRole(userId: Int, role: String) async throws -> JSONDict {
        try await post("/api/admin/users/\(userId)/role", ["role": role], auth: true)
    }
}
