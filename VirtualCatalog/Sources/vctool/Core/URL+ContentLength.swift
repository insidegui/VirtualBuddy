import Foundation

extension URL {
    func contentLength() async throws -> Int64 {
        var request = URLRequest(url: self)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw "Invalid response"
        }

        guard httpResponse.statusCode < 300 else {
            throw "HTTP \(httpResponse.statusCode)"
        }

        guard let stringValue = httpResponse.value(forHTTPHeaderField: "content-length"),
              let length = Int64(stringValue)
        else {
            throw "Missing or invalid Content-Length header"
        }

        return length
    }
}
