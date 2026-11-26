import Foundation
import Testing
@testable import VirtualBuddy

/// Runs the control server on a socket of its own and talks to it the way the command-line tool does.
/// The tests are hosted by the app, so the test process is the code the server expects on the other end.
@MainActor
struct ControlServerTests {
    private final class Recorder {
        var requests = [ControlRequest]()
        var cancellations = 0
        var isAuthorized = true
    }

    private let directory = URL(fileURLWithPath: "/private/tmp/vbctl-tests-\(UUID().uuidString.prefix(8))")
    private var socketURL: URL { directory.appendingPathComponent("control.sock") }

    private func withServer(
        _ recorder: Recorder,
        handler: @escaping ControlServer.Handler,
        _ body: (ControlServer) async throws -> Void
    ) async throws {
        let server = ControlServer(socketURL: socketURL, runtimeDirectory: directory) {
            guard recorder.isAuthorized else { throw ControlError(.accessDisabled, "Command-line access is turned off.") }
        } handler: { request, report in
            recorder.requests.append(request)
            return try await handler(request, report)
        }
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try server.start()
        try await body(server)
    }

    private func connect() throws -> ControlConnection {
        try #require(try ControlConnection.open(socketURL), "Nothing is listening on the socket")
    }

    /// Fails the test instead of hanging when the server never answers.
    private func receive(from connection: ControlConnection) async throws -> ControlReply {
        try await withThrowingTaskGroup(of: ControlReply.self) { group in
            group.addTask { try await connection.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                connection.close()
                throw CocoaError(.userCancelled)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func exchange(_ request: ControlRequest) async throws -> [ControlReply] {
        let socket = try connect()
        defer { socket.close() }
        try await socket.send(request)
        var replies = [ControlReply]()
        while true {
            let reply = try await receive(from: socket)
            replies.append(reply)
            if case .event = reply { continue }
            return replies
        }
    }

    private func message(_ reply: ControlReply?) -> String? {
        guard case .success(.message(let text)) = reply else { return nil }
        return text
    }

    private func failure(_ reply: ControlReply?) -> ControlError? {
        guard case .failure(let error) = reply else { return nil }
        return error
    }

    @Test func answersWithProgressAndThenTheResult() async throws {
        let recorder = Recorder()
        try await withServer(recorder) { request, report in
            await report("Working…")
            return .message("Done in \(request.timeout ?? 0)")
        } _: { _ in
            let replies = try await exchange(ControlRequest(command: .library, timeout: 5))
            #expect(replies.count == 2)
            guard case .event("Working…") = replies.first else {
                Issue.record("Progress should come before the result" as Comment)
                return
            }
            #expect(message(replies.last) == "Done in 5.0")
            #expect(recorder.requests.count == 1)

            var attributes = stat()
            #expect(lstat(socketURL.path, &attributes) == 0)
            #expect(attributes.st_mode & 0o777 == 0o600)
            #expect(lstat(directory.path, &attributes) == 0)
            #expect(attributes.st_mode & 0o777 == 0o700)
        }
    }

    @Test func reportsFailuresWithTheirCode() async throws {
        try await withServer(Recorder()) { request, _ in
            if case .open = request.command { throw ControlError(.notFound, "No such virtual machine.") }
            throw CocoaError(.fileNoSuchFile)
        } _: { _ in
            let missing = try await exchange(ControlRequest(command: .open(vm: "Tahoe")))
            #expect(failure(missing.last) == ControlError(.notFound, "No such virtual machine."))
            let other = try await exchange(ControlRequest(command: .library))
            #expect(failure(other.last)?.code == .failure)
        }
    }

    @Test func checksTheSettingForEveryRequestAndRefusesOtherVersions() async throws {
        let recorder = Recorder()
        try await withServer(recorder) { _, _ in .message("Done") } _: { _ in
            let allowed = try await exchange(ControlRequest(command: .library))
            #expect(message(allowed.last) == "Done")

            recorder.isAuthorized = false
            let refused = try await exchange(ControlRequest(command: .library))
            #expect(failure(refused.last)?.code == .accessDisabled)

            recorder.isAuthorized = true
            var newer = ControlRequest(command: .library)
            newer.version = ControlProtocol.version + 1
            let mismatched = try await exchange(newer)
            #expect(failure(mismatched.last)?.code == .incompatibleVersion)

            let socket = try connect()
            defer { socket.close() }
            try await socket.send(["command": "from another version"])
            let unreadable = try await receive(from: socket)
            #expect(failure(unreadable)?.code == .incompatibleVersion)

            #expect(recorder.requests.count == 1)
        }
    }

    @Test func stopsWaitingWhenTheToolGoesAway() async throws {
        let recorder = Recorder()
        try await withServer(recorder) { _, report in
            await report("Waiting…")
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                recorder.cancellations += 1
                throw error
            }
            return .message("Too late")
        } _: { _ in
            let socket = try connect()
            try await socket.send(ControlRequest(command: .library))
            _ = try await receive(from: socket)
            socket.close()

            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while recorder.cancellations == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(recorder.cancellations == 1)
        }
    }

    @Test func closesTheSocketWhenItStopsAndCanStartAgain() async throws {
        let recorder = Recorder()
        try await withServer(recorder) { _, _ in .message("Done") } _: { server in
            #expect(server.isListening)
            server.stop()
            #expect(!server.isListening)
            #expect(!FileManager.default.fileExists(atPath: socketURL.path))
            #expect(try ControlConnection.open(socketURL) == nil)

            try server.start()
            let replies = try await exchange(ControlRequest(command: .library))
            #expect(message(replies.last) == "Done")
        }
    }
}
