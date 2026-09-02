import Foundation

/// Adresse du serveur de chat.
///
/// Le serveur écoute en http:// sur le port 10028, à l'adresse IP directe
/// 151.240.30.3 (pas de nom de domaine, pas de certificat).
///
/// ⚠️ Comme le serveur n'a pas de TLS, il faut autoriser le trafic HTTP en
/// clair vers cette IP dans Info.plist (NSAppTransportSecurity /
/// NSExceptionDomains) sinon iOS bloquera silencieusement les requêtes.
enum Config {
    static let host = "151.240.30.3:10028"
    static let baseURL = "http://\(host)"
    static let wsURL = "ws://\(host)"
}
