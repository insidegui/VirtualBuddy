import Foundation
import notify

/// Describes a type of notification delivery system.
public enum NotificationCenterType: String, Codable {
    /// The distributed center (`DistributedNotificationCenter`).
    case distributed
    /// The Darwin notification center (`notify_register_dispatch`).
    case notify
}

struct LibNotifyError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
    var failureReason: String? { message }

    init(code: UInt32) {
        let name: String
        switch Int32(code) {
        case NOTIFY_STATUS_OK: name = "NOTIFY_STATUS_OK"
        case NOTIFY_STATUS_INVALID_NAME: name = "NOTIFY_STATUS_INVALID_NAME"
        case NOTIFY_STATUS_INVALID_TOKEN: name = "NOTIFY_STATUS_INVALID_TOKEN"
        case NOTIFY_STATUS_INVALID_PORT: name = "NOTIFY_STATUS_INVALID_PORT"
        case NOTIFY_STATUS_INVALID_FILE: name = "NOTIFY_STATUS_INVALID_FILE"
        case NOTIFY_STATUS_INVALID_SIGNAL: name = "NOTIFY_STATUS_INVALID_SIGNAL"
        case NOTIFY_STATUS_INVALID_REQUEST: name = "NOTIFY_STATUS_INVALID_REQUEST"
        case NOTIFY_STATUS_NOT_AUTHORIZED: name = "NOTIFY_STATUS_NOT_AUTHORIZED"
        case NOTIFY_STATUS_OPT_DISABLE: name = "NOTIFY_STATUS_OPT_DISABLE"
        case NOTIFY_STATUS_SERVER_NOT_FOUND: name = "NOTIFY_STATUS_SERVER_NOT_FOUND"
        case NOTIFY_STATUS_NULL_INPUT: name = "NOTIFY_STATUS_NULL_INPUT"
        default: name = "unknown"
        }
        self.message = "Notify error \(code) (\(name))"
    }
}

/// Abstracts subscribing to notifications on multiple notification center types.
final class NotificationCenterObserver: @unchecked Sendable {

    struct Key: Hashable {
        var id: UUID
        var type: NotificationCenterType
        var name: String
    }

    @MainActor
    private var observers = [Key: Any]()

    @MainActor
    @discardableResult
    func addObserver(id: UUID, for name: String, on type: NotificationCenterType, using block: @escaping @Sendable () -> Void) throws -> Key {
        let observer: Any

        switch type {
        case .distributed:
            observer = DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: nil) { _ in
                block()
            }
        case .notify:
            var notificationToken: Int32 = 0

            let status = notify_register_dispatch(
                name,
                &notificationToken,
                .main,
                { _ in block() }
            )

            guard status == NOTIFY_STATUS_OK else {
                throw LibNotifyError(code: status)
            }

            observer = notificationToken
        }

        let key = Key(id: id, type: type, name: name)

        observers[key] = observer

        return key
    }

    @MainActor
    func removeObserver(_ key: Key) {
        guard let observer = observers[key] else { return }

        invalidate(key, observer: observer)
    }

    @MainActor
    private func invalidate(_ key: Key, observer: Any) {
        switch key.type {
        case .distributed:
            DistributedNotificationCenter.default().removeObserver(observer)
        case .notify:
            if let token = observer as? Int32 {
                _ = notify_cancel(token)
            }
        }
    }

    nonisolated func invalidate() {
        DispatchQueue.main.async {
            self.observers.forEach {
                self.invalidate($0.key, observer: $0.value)
            }
        }
    }

    deinit {
        #if DEBUG
        print("[NotificationCenterObserver] Bye bye 👋")
        #endif

        invalidate()
    }

}
