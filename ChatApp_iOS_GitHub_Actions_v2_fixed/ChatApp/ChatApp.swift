import SwiftUI
import UserNotifications

@main
struct ChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isLoggedIn = Session.isLoggedIn()

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    ConversationsView(isLoggedIn: $isLoggedIn)
                } else {
                    LoginView(isLoggedIn: $isLoggedIn)
                }
            }
            .onChange(of: isLoggedIn) {
                if isLoggedIn {
                    WSManager.shared.connect()
                    NotificationHelper.requestAuthorization()
                }
            }
            .onAppear {
                if isLoggedIn {
                    WSManager.shared.connect()
                    NotificationHelper.requestAuthorization()
                }
            }
        }
    }
}

/// Suit le passage premier plan / arrière-plan (équivalent de
/// AppState.isAppInForeground côté Android, mis à jour depuis les
/// callbacks de cycle de vie de l'Activity/du Service) et relaie les
/// messages WebSocket globaux vers des notifications locales quand l'app
/// n'est pas au premier plan.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let globalListener = WSListenerBox()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        globalListener.onMessage = { [weak self] data in
            self?.handleGlobalMessage(data)
        }
        WSManager.shared.addListener(globalListener)

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            AppState.shared.isAppInForeground = true
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            AppState.shared.isAppInForeground = false
        }
        return true
    }

    private func handleGlobalMessage(_ data: JSONDict) {
        guard data.string("type") == "message" else { return }
        guard !AppState.shared.isAppInForeground else { return }
        let senderId = data.int("sender_id")
        guard senderId != Session.userId else { return }
        let conversationId = data.int("conversation_id")
        let text = data.isNull("content") ? "📷 Message" : data.string("content")
        NotificationHelper.notifyNewMessage(conversationId: conversationId, senderName: "Nouveau message", text: text)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
