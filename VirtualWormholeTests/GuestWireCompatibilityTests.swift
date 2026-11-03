import Foundation
import Testing
import VMBridge
@testable import VirtualWormhole

/// Frozen payloads from the protocol preceding the service extraction. Round
/// trips alone would miss a simultaneous, incompatible change at both endpoints.
struct GuestWireCompatibilityTests {
    private let token = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    @Test func existingMessageIdentifiersAndPayloads() throws {
        try check(InitializeGuest.self, id: "InitializeGuest", json: #"{"session":"12345678-1234-1234-1234-123456789ABC"}"#)
        try check(InitializeGuestReply.self, id: "InitializeGuestReply", json: #"{"notifications":["com.apple.shieldWindowRaised"]}"#)
        try check(ClipboardUpdate.self, id: "ClipboardUpdate", json: #"{"session":"12345678-1234-1234-1234-123456789ABC","revision":7,"items":[{"type":"public.utf8-plain-text","data":"aGVsbG8="}]}"#)
        try check(GuestNotification.self, id: "GuestNotification", json: #"{"session":"12345678-1234-1234-1234-123456789ABC","name":"com.apple.shieldWindowRaised"}"#)
        try check(DesktopPictureUpdate.self, id: "DesktopPictureUpdate", json: #"{"session":"12345678-1234-1234-1234-123456789ABC","type":"public.heic","content":"AQID"}"#)
        try check(ExportDefaults.self, id: "ExportDefaults", json: #"{"session":"12345678-1234-1234-1234-123456789ABC","operation":"12345678-1234-1234-1234-123456789ABC","domain":"com.apple.finder"}"#)
        try check(ExportDefaultsReply.self, id: "ExportDefaultsReply", json: #"{"inline":{"_0":"AQID"}}"#)
        try check(ExportDefaultsReply.self, id: "ExportDefaultsReply", json: #"{"file":{}}"#)
        try check(ExportDefaultsReply.self, id: "ExportDefaultsReply", json: #"{"failure":{"_0":"unavailable"}}"#)
        #expect(GuestCommunication.port == 51_780)
    }

    @Test func existingTransferMetadata() throws {
        for purpose in [TransferIdentity.Purpose.clipboard, .defaults] {
            let metadata = TransferIdentity(session: token, operation: token, purpose: purpose, revision: 7).metadata
            #expect(metadata.name == "\(purpose.rawValue).plist")
            #expect(metadata.contentType == "com.apple.property-list")
            #expect(metadata.userInfo == ["session": token.uuidString, "operation": token.uuidString, "purpose": purpose.rawValue, "revision": "7"])
            let decoded = try #require(TransferIdentity(metadata))
            #expect(decoded.session == token)
            #expect(decoded.operation == token)
            #expect(decoded.purpose == purpose)
            #expect(decoded.revision == 7)
        }
    }

    private func check<M: VMMessage>(_ type: M.Type, id: String, json: String) throws {
        #expect(M.messageID == id)
        let fixture = Data(json.utf8)
        let decoded = try JSONDecoder().decode(type, from: fixture)
        let actual = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary)
        let expected = try #require(JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
        #expect(actual == expected)
    }
}
