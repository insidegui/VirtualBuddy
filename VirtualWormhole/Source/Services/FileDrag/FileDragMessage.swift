import Foundation

public struct FileDragLocation: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

public struct FileDragMessage: WHPayload, Hashable {
    public enum Action: String, Codable, Hashable, Sendable {
        case begin
        case update
        case drop
        case cancel
        case status
        case result
    }

    public enum Status: String, Codable, Hashable, Sendable {
        case staged
        case beginReceived
        case sourceReady
        case inputPermissionMissing
        case mouseDownPosted
        case pointerObserved
        case sessionCreated
        case sessionWillBegin
        case sessionMoved
        case dropReceived
        case mouseUpPosted
        case sessionStartTimedOut
    }

    public var action: Action
    public var sessionID: UUID
    public var location: FileDragLocation?
    public var operation: UInt?
    public var status: Status?

    public init(
        action: Action,
        sessionID: UUID,
        location: FileDragLocation? = nil,
        operation: UInt? = nil,
        status: Status? = nil
    ) {
        self.action = action
        self.sessionID = sessionID
        self.location = location
        self.operation = operation
        self.status = status
    }
}
