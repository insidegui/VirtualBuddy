import CryptoKit
import Foundation
import os
import Testing
@testable import AppStoreConnectDevices

struct DeviceRegistrationTests {
    @Test func jwtUsesTheTeamIssuerAndAnES256Signature() throws {
        let key = P256.Signing.PrivateKey()
        let issuer = UUID()
        let credential = RegistrationCredential(issuer: issuer, keyID: "ABC1234567", secret: key.rawRepresentation)
        let token = try credential.token(at: Date(timeIntervalSince1970: 1000))
        let parts = token.components(separatedBy: ".")
        #expect(parts.count == 3)
        func decode(_ text: String) throws -> Data {
            let base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            return try #require(Data(base64Encoded: base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)))
        }
        let header = try JSONDecoder().decode([String: String].self, from: decode(parts[0]))
        #expect(header == ["typ": "JWT", "kid": "ABC1234567", "alg": "ES256"])
        let claims = try #require(try JSONSerialization.jsonObject(with: decode(parts[1])) as? [String: Any])
        #expect(claims["iss"] as? String == issuer.uuidString.lowercased())
        #expect(claims["aud"] as? String == "appstoreconnect-v1")
        #expect(claims["iat"] as? Int == 1000)
        #expect(claims["exp"] as? Int == 1300)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
        #expect(key.publicKey.isValidSignature(signature, for: Data(parts.prefix(2).joined(separator: ".").utf8)))
    }

    @Test func registrationLooksUpTheExactMacBeforeCreatingIt() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeviceFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let key = RegistrationCredential(issuer: UUID(), keyID: "ABC1234567", secret: P256.Signing.PrivateKey().rawRepresentation)
        let reads = OSAllocatedUnfairLock(initialState: [String]())
        let api = MacDeviceRegistration(session: session) { team, reason in
            reads.withLock { $0.append(team + ": " + reason) }
            return key
        }
        #expect(try await api.lookup(udid: "new-mac", teamID: "TEAM") == nil)
        #expect(try await api.register(name: "Test VM", udid: "new-mac", teamID: "TEAM") == .enabled)
        // A lookup followed by creation reads the protected key once, with a reason the user can judge.
        #expect(reads.withLock { $0 } == ["TEAM: check whether this Mac is registered with team TEAM", "TEAM: register “Test VM” with team TEAM"])
        #expect(try await api.register(name: "Test VM", udid: "disabled-mac", teamID: "TEAM") == .disabled)
        await #expect(throws: DeviceRegistrationError.self) { try await api.lookup(udid: "wrong-case", teamID: "TEAM") }
    }
}

private final class DeviceFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.host == "api.appstoreconnect.apple.com" && url.path == "/v1/devices")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            var result: Any
            if request.httpMethod == "GET" {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(query.contains(URLQueryItem(name: "filter[platform]", value: "MAC_OS")))
                let udid = try #require(query.first { $0.name == "filter[udid]" }?.value)
                let device = ["attributes": ["udid": udid == "wrong-case" ? "WRONG-CASE" : udid, "platform": "MAC_OS", "status": "DISABLED"]]
                result = udid == "new-mac" ? [] : [device]
            } else {
                #expect(request.httpMethod == "POST")
                let body: Data
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    body = Data(buffer.prefix(max(count, 0)))
                } else { body = try #require(request.httpBody) }
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: [String: Any]])
                #expect(json["data"]?["type"] as? String == "devices")
                #expect(json["data"]?["attributes"] as? [String: String] == ["name": "Test VM", "platform": "MAC_OS", "udid": "new-mac"])
                result = ["attributes": ["udid": "new-mac", "platform": "MAC_OS", "status": "ENABLED"]]
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: ["data": result]))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
