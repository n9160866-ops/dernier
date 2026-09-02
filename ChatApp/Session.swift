import Foundation

/// Stocke le token JWT + l'identité de l'utilisateur connecté, sur l'appareil.
/// Équivalent de Session.kt (SharedPreferences) via UserDefaults.
///
/// ⚠️ UserDefaults n'est pas chiffré. C'est l'équivalent direct de
/// SharedPreferences côté Android (qui ne l'est pas non plus en clair),
/// donc le comportement reste identique à l'original. Pour un vrai
/// renforcement de la sécurité sur iOS, le token JWT pourrait être déplacé
/// vers le Keychain (via une petite couche KeychainWrapper) sans changer
/// l'API ci-dessous.
enum Session {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let token = "token"
        static let userId = "user_id"
        static let username = "username"
        static let role = "role"
    }

    static var token: String? {
        get { defaults.string(forKey: Key.token) }
        set { defaults.set(newValue, forKey: Key.token) }
    }

    static var userId: Int {
        get { defaults.object(forKey: Key.userId) != nil ? defaults.integer(forKey: Key.userId) : -1 }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    static var username: String? {
        get { defaults.string(forKey: Key.username) }
        set { defaults.set(newValue, forKey: Key.username) }
    }

    static var role: String? {
        get { defaults.string(forKey: Key.role) ?? "user" }
        set { defaults.set(newValue, forKey: Key.role) }
    }

    static func isLoggedIn() -> Bool {
        guard let token = token else { return false }
        return !token.isEmpty
    }

    static func clear() {
        [Key.token, Key.userId, Key.username, Key.role].forEach { defaults.removeObject(forKey: $0) }
    }
}
