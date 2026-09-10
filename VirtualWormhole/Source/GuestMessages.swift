import Foundation
import VMBridge

public enum GuestCommunication {
    public static let port: UInt32 = 51_780
}

struct InitializeGuest: VMMessage { let session: UUID }
struct InitializeGuestReply: VMMessage { let notifications: Set<String> }

struct ClipboardItem: Codable, Sendable, Equatable {
    let type: String
    let data: Data
}

struct ClipboardUpdate: VMMessage {
    let session: UUID
    let revision: UInt64
    let items: [ClipboardItem]
}

struct GuestNotification: VMMessage {
    let session: UUID
    let name: String
}

public struct GuestDesktopPicture: Sendable {
    public let type: String
    public let content: Data
}

struct DesktopPictureUpdate: VMMessage {
    let session: UUID
    let type: String
    let content: Data
}

struct ExportDefaults: VMMessage {
    let session: UUID
    let operation: UUID
    let domain: String
}

enum ExportDefaultsReply: VMMessage {
    case inline(Data)
    case file
    case failure(String)
}

struct TransferIdentity: Sendable {
    enum Purpose: String { case clipboard, defaults }
    let session: UUID
    let operation: UUID
    let purpose: Purpose
    let revision: UInt64

    var metadata: BulkTransferMetadata {
        .init(name: "\(purpose.rawValue).plist", contentType: "com.apple.property-list", userInfo: [
            "session": session.uuidString, "operation": operation.uuidString,
            "purpose": purpose.rawValue, "revision": String(revision)
        ])
    }

    init(session: UUID, operation: UUID, purpose: Purpose, revision: UInt64 = 0) {
        self.session = session
        self.operation = operation
        self.purpose = purpose
        self.revision = revision
    }

    init?(_ metadata: BulkTransferMetadata) {
        guard let session = metadata.userInfo["session"].flatMap(UUID.init(uuidString:)),
              let operation = metadata.userInfo["operation"].flatMap(UUID.init(uuidString:)),
              let purpose = metadata.userInfo["purpose"].flatMap(Purpose.init(rawValue:)),
              let revision = metadata.userInfo["revision"].flatMap(UInt64.init) else { return nil }
        self.init(session: session, operation: operation, purpose: purpose, revision: revision)
    }
}

enum GuestSessionError: LocalizedError {
    case disconnected, invalidReply, unavailableDomain, remote(String)
    var errorDescription: String? {
        switch self {
        case .disconnected: "The connection to VirtualBuddy ended."
        case .invalidReply: "The host returned an invalid response."
        case .unavailableDomain: "This defaults domain is not available for import."
        case .remote(let message): message
        }
    }
}
