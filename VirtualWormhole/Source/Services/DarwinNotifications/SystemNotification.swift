//
//  SystemNotification.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 08/03/23.
//

import Foundation
import notify

/// Swift wrapper for the `notify_register_dispatch()` API.
public final class SystemNotification {

    public struct LibNotifyError: LocalizedError {
        public var errorDescription: String?

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
            self.errorDescription = "Notify error \(code) (\(name))"
        }
    }

    public let name: String
    private let queue: DispatchQueue
    private let callback: (SystemNotification) -> Void
    public private(set) var notificationToken: Int32 = 0
    private var activated = false

    public init(with name: String, queue: DispatchQueue = .main, callback: @escaping (SystemNotification) -> Void) {
        self.name = name
        self.queue = queue
        self.callback = callback
    }

    public init(with name: String, queue: DispatchQueue = .main, callback: @escaping () -> Void) {
        self.name = name
        self.queue = queue
        self.callback = { _ in callback() }
    }

    public func activate() throws {
        guard !activated else { return }

        let status = notify_register_dispatch(
            name,
            &notificationToken,
            queue,
            notificationReceived
        )

        guard status == NOTIFY_STATUS_OK else {
            throw LibNotifyError(code: status)
        }

        activated = true
    }

    public func invalidate() {
        guard activated else { return }

        notify_cancel(notificationToken)
        notificationToken = 0

        activated = false
    }

    deinit { invalidate() }

    private func notificationReceived(_ token: Int32) {
        callback(self)
    }

    func getState() throws -> UInt64 {
        var state: UInt64 = 0
        let status = notify_get_state(notificationToken, &state)

        guard status == NOTIFY_STATUS_OK else {
            throw LibNotifyError(code: status)
        }

        return state
    }

}
