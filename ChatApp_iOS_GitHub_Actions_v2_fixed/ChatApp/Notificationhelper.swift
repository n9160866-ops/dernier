import Foundation
import UserNotifications

/// Notifications locales pour les nouveaux messages reçus par WebSocket
/// pendant que l'app est en arrière-plan. Équivalent partiel de
/// NotificationHelper.kt + ChatForegroundService.kt.
///
/// ⚠️ Différence importante avec Android : iOS n'autorise pas un service
/// qui garde une WebSocket ouverte indéfiniment en arrière-plan. Tant que
/// l'app n'est pas relancée au premier plan (ou tant qu'un vrai serveur de
/// push APNs n'est pas branché côté back-end), les messages reçus pendant
/// que l'app est totalement fermée ne déclencheront pas de notification.
/// Cette classe couvre le cas "app en arrière-plan mais encore active"
/// (WebSocket encore connectée) via une notification locale.
enum NotificationHelper {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notifyNewMessage(conversationId: Int, senderName: String, text: String) {
        // Pas de notif si la conversation est déjà ouverte à l'écran.
        guard AppState.shared.openConversationId != conversationId else { return }

        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = text
        content.sound = .default
        content.userInfo = ["conversation_id": conversationId]

        let request = UNNotificationRequest(
            identifier: "message_\(conversationId)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func clearMessageNotifications(conversationId: Int) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { ($0.request.content.userInfo["conversation_id"] as? Int) == conversationId }
                .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
