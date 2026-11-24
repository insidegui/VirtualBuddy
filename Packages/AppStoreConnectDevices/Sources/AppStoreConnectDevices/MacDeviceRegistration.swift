import Foundation

/// The only network operations are an exact device lookup and registration of one Mac.
public struct MacDeviceRegistration: Sendable {
    public enum Status: Equatable, Sendable { case enabled, disabled }
    private let credential: @Sendable (String) async throws -> RegistrationCredential
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.appstoreconnect.apple.com/v1/devices")!

    public init(keys: DeviceRegistrationKeys) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        self.init(session: URLSession(configuration: configuration), credential: { try await keys.credential(for: $0) })
    }

    init(session: URLSession, credential: @escaping @Sendable (String) async throws -> RegistrationCredential) {
        self.session = session
        self.credential = credential
    }

    private struct Device: Decodable {
        struct Attributes: Decodable { let udid, platform, status: String }
        let attributes: Attributes

        func status(for udid: String) throws -> Status {
            guard attributes.platform == "MAC_OS", attributes.udid == udid else {
                throw DeviceRegistrationError("Apple returned a different Mac identifier. Check the registered provisioning UDID.")
            }
            switch attributes.status {
            case "ENABLED": return .enabled
            case "DISABLED": return .disabled
            default: throw DeviceRegistrationError("Apple reports device status \(attributes.status). Check the device in your developer account.")
            }
        }
    }
    private struct Response<Value: Decodable>: Decodable { let data: Value }
    private struct ServiceFailure: Decodable {
        struct Detail: Decodable { let detail: String? }
        let errors: [Detail]
    }
    private struct HTTPFailure: LocalizedError {
        let code: Int
        let detail: String?
        var errorDescription: String? { "App Store Connect (\(code)). " + (detail ?? HTTPURLResponse.localizedString(forStatusCode: code)) }
    }

    public func lookup(udid: String, teamID: String) async throws -> Status? {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "filter[udid]", value: udid), URLQueryItem(name: "filter[platform]", value: "MAC_OS")]
        let data = try await request(URLRequest(url: components.url!), team: teamID)
        let matches = try JSONDecoder().decode(Response<[Device]>.self, from: data).data
        return try matches.first?.status(for: udid)
    }

    /// Call after the user approves consuming a device slot on this team.
    public func register(name: String, udid: String, teamID: String) async throws -> Status {
        if let existing = try await lookup(udid: udid, teamID: teamID) { return existing }
        var create = URLRequest(url: Self.endpoint)
        create.httpMethod = "POST"
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["type": "devices", "attributes": [
            "name": name, "platform": "MAC_OS", "udid": udid
        ]]])
        do {
            let data = try await request(create, team: teamID)
            return try JSONDecoder().decode(Response<Device>.self, from: data).data.status(for: udid)
        } catch let failure as HTTPFailure where failure.code == 409 {
            // Two hosts can register the same Mac between the lookup and creation.
            if let existing = try await lookup(udid: udid, teamID: teamID) { return existing }
            throw failure
        }
    }

    private func request(_ request: URLRequest, team: String) async throws -> Data {
        var request = request
        let key = try await credential(team)
        request.setValue("Bearer " + (try key.token(at: Date())), forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request, delegate: NoRedirect())
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(ServiceFailure.self, from: data)
            throw HTTPFailure(code: response.statusCode, detail: failure?.errors.first?.detail)
        }
        return data
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
