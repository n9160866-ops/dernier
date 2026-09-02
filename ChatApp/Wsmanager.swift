import Foundation

/// Boîte à listener légère : chaque vue en garde une instance (comme un
/// "tag" d'identité) et fixe sa closure `onMessage`. Permet à WSManager de
/// stocker des références faibles sans exiger un protocole Hashable.
final class WSListenerBox: NSObject {
    var onMessage: ((JSONDict) -> Void)?
}

/// Connexion WebSocket unique, partagée par toute l'appli (singleton), pour :
///  - envoyer/recevoir les messages en direct (privés + groupes)
///  - la présence en ligne/hors ligne, l'indicateur "en train d'écrire"
///  - la signalisation d'appel WebRTC (offer/answer/ICE/end)
///
/// Se reconnecte automatiquement si la connexion tombe, tant qu'un token
/// est présent dans la Session. Équivalent de WsManager.kt, basé sur
/// URLSessionWebSocketTask plutôt que sur OkHttp.
final class WSManager: NSObject {
    static let shared = WSManager()
    private override init() { super.init() }

    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?
    private let listeners = NSHashTable<WSListenerBox>.weakObjects()
    private var shouldReconnect = false

    func addListener(_ listener: WSListenerBox) {
        listeners.add(listener)
    }

    func removeListener(_ listener: WSListenerBox) {
        listeners.remove(listener)
    }

    func connect() {
        guard task == nil else { return }
        shouldReconnect = true
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session
        guard let url = URL(string: Config.wsURL) else { return }
        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        receiveLoop(on: newTask)
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        urlSession = nil
    }

    func send(_ json: JSONDict) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    func sendMessage(conversationId: Int, text: String) {
        send([
            "type": "message",
            "conversation_id": conversationId,
            "content": text,
            "msg_type": "text"
        ])
    }

    func sendTyping(conversationId: Int, isTyping: Bool) {
        send(["type": "typing", "conversation_id": conversationId, "is_typing": isTyping])
    }

    // MARK: - Réception

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                self.handleClosed()
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let obj = try? JSONParsing.dict(from: data) {
                    let snapshot = self.listeners.allObjects
                    DispatchQueue.main.async {
                        for listener in snapshot { listener.onMessage?(obj) }
                    }
                }
                // Toujours re-brancher tant que cette tâche est encore la tâche active.
                if self.task === task {
                    self.receiveLoop(on: task)
                }
            }
        }
    }

    private func handleClosed() {
        task = nil
        urlSession = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, let token = Session.token, !token.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.connect()
        }
    }
}

extension WSManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let auth: JSONDict = ["type": "auth", "token": Session.token ?? NSNull()]
        send(auth)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleClosed()
    }
}
