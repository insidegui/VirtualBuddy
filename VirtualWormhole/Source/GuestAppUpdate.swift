import Foundation
import Observation
import Security
import CryptoKit
import VMBridge

/// The code identity is needed because local builds may share a build number.
public struct GuestAppIdentity: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let codeHash: Data
    public let minimumOS: String

    public init(version: String, build: Int, codeHash: Data, minimumOS: String) {
        self.version = version
        self.build = build
        self.codeHash = codeHash
        self.minimumOS = minimumOS
    }

    public init(bundle: Bundle) throws {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildString = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = Int(buildString), build > 0,
              let minimumOS = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
              Self.versionComponents(minimumOS) != nil else {
            throw GuestAppUpdateError.invalidPackage
        }
        var code: SecStaticCode?
        try Self.check(SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code))
        guard let code else { throw GuestAppUpdateError.invalidPackage }
        var information: CFDictionary?
        try Self.check(SecCodeCopySigningInformation(code, [], &information))
        guard let hash = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else {
            throw GuestAppUpdateError.invalidPackage
        }
        self.init(version: version, build: build, codeHash: hash, minimumOS: minimumOS)
    }

    public func supports(osVersion: String) -> Bool {
        guard let minimum = Self.versionComponents(minimumOS),
              let actual = Self.versionComponents(osVersion) else { return false }
        return !actual.lexicographicallyPrecedes(minimum)
    }

    public func isUpdate(over current: GuestAppIdentity) -> Bool {
        build > current.build || (build == current.build && codeHash != current.codeHash)
    }

    /// Mounted media has no trusted chronology for two different builds with the same number.
    public static func shouldAutomaticallyInstallMountedBuild(_ candidate: Int, over current: Int) -> Bool {
        candidate > current
    }

    private static func versionComponents(_ string: String) -> [Int]? {
        let components = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = components.compactMap { Int($0) }
        guard values.count == components.count, values[0] > 0 else { return nil }
        return values + Array(repeating: 0, count: 3 - values.count)
    }

    static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown code-signature error"
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Could not read the VirtualBuddyGuest code signature: \(reason). (OSStatus \(status))"
            ])
        }
    }
}

public struct GuestAppUpdatePackage: Codable, Equatable, Sendable {
    public let identity: GuestAppIdentity
    public let byteCount: Int64
    public let sha256: Data
    public static let maximumBytes: Int64 = 256 * 1024 * 1024

    public init(identity: GuestAppIdentity, byteCount: Int64, sha256: Data) {
        self.identity = identity
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum GuestAppUpdateError: LocalizedError {
    case invalidPackage, unsupported, busy, interrupted, confirmationTimedOut
    public var errorDescription: String? {
        switch self {
        case .invalidPackage: "The VirtualBuddyGuest update is invalid or does not match the expected app."
        case .unsupported: "This guest cannot install this update automatically. Export the installer and open it inside the virtual machine."
        case .busy: "A VirtualBuddyGuest update is already in progress."
        case .interrupted: "The update was interrupted. Reconnect to the guest and try again."
        case .confirmationTimedOut: "The updated guest app did not reconnect. Open VirtualBuddyGuest inside the virtual machine or install the update manually."
        }
    }
}

/// The guest app supplies installation behavior; the transport never installs apps on the host.
@MainActor
public struct PreparedGuestAppUpdate {
    public let launchInstaller: () async throws -> Void
    public let terminateApp: () -> Void
    public let discard: () -> Void

    public init(launchInstaller: @escaping () async throws -> Void, terminateApp: @escaping () -> Void, discard: @escaping () -> Void) {
        self.launchInstaller = launchInstaller
        self.terminateApp = terminateApp
        self.discard = discard
    }
}

struct GuestAppUpdateReport: Codable, Sendable {
    let identity: GuestAppIdentity
    let osVersion: String
}

struct BeginGuestAppUpdate: VMMessage {
    let session: UUID
    let operation: UUID
    let package: GuestAppUpdatePackage
}
struct CancelGuestAppUpdate: VMMessage {
    let session: UUID
    let operation: UUID
}
struct CommitGuestAppUpdate: VMMessage {
    let session: UUID
    let operation: UUID
}
enum GuestAppUpdateReply: VMMessage {
    case accepted
    case failure(String)
}
struct GuestAppUpdateProgress: VMMessage {
    let session: UUID
    let operation: UUID
    let error: String?
}

@MainActor @Observable
public final class GuestAppUpdateState {
    public enum Phase: Equatable {
        case idle, preparing, transferring, installing, reconnecting, succeeded, failed
    }
    public internal(set) var phase: Phase = .idle
    public var target: GuestAppIdentity?
    public internal(set) var installed: GuestAppIdentity?
    public internal(set) var reportedBuild: Int?
    public internal(set) var osVersion: String?
    public internal(set) var supportsRemoteUpdate = false
    public internal(set) var isConnected = false
    public internal(set) var errorMessage: String?

    public var isBusy: Bool { [.preparing, .transferring, .installing, .reconnecting].contains(phase) }
    public var isCompatible: Bool {
        guard let target, let osVersion else { return false }
        return target.supports(osVersion: osVersion)
    }
    public var updateAvailable: Bool {
        guard isCompatible, let target else { return false }
        if let installed { return target.isUpdate(over: installed) }
        return reportedBuild.map { target.build > $0 } ?? false
    }
    public var canUpdate: Bool { isConnected && supportsRemoteUpdate && updateAvailable && !isBusy }
    public init(target: GuestAppIdentity? = nil, installed: GuestAppIdentity? = nil,
                reportedBuild: Int? = nil, osVersion: String? = nil,
                supportsRemoteUpdate: Bool = false, isConnected: Bool = false,
                phase: Phase = .idle, errorMessage: String? = nil) {
        self.target = target
        self.installed = installed
        self.reportedBuild = reportedBuild
        self.osVersion = osVersion
        self.supportsRemoteUpdate = supportsRemoteUpdate
        self.isConnected = isConnected
        self.phase = phase
        self.errorMessage = errorMessage
    }
}

@MainActor
final class AppUpdateGuestService: GuestService {
    nonisolated static let capability = "guestAppUpdate.v1"
    let state = GuestAppUpdateState()
    var prepareInstallation: ((URL, GuestAppUpdatePackage) async throws -> PreparedGuestAppUpdate)?
    var report: GuestAppUpdateReport?
    private var operation: UUID?
    private var package: GuestAppUpdatePackage?
    private var prepared: PreparedGuestAppUpdate?
    private var receiving = false
    private var committed = false
    private var committing = false
    private var confirmationTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var expectedIdentity: GuestAppIdentity?
    var confirmationTimeout: Duration = .seconds(180)
    override var transferPurpose: TransferIdentity.Purpose? { .appUpdate }

    override func subscriptions() -> [Subscription] {
        let begins = connection.requests(of: BeginGuestAppUpdate.self, reply: GuestAppUpdateReply.self)
        let commits = connection.requests(of: CommitGuestAppUpdate.self, reply: GuestAppUpdateReply.self)
        let progress = connection.messages(of: GuestAppUpdateProgress.self)
        let cancellations = connection.messages(of: CancelGuestAppUpdate.self)
        return [
            { for await cancellation in cancellations { await self.cancel(cancellation) } },
            { for await request in begins { await self.begin(request) } },
            { for await request in commits { await self.commit(request) } },
            { for await update in progress { await self.receive(update) } }
        ]
    }

    func connected(report: GuestAppUpdateReport?, supportsUpdates: Bool) {
        state.isConnected = true
        state.supportsRemoteUpdate = supportsUpdates
        state.installed = report?.identity
        state.reportedBuild = report?.identity.build
        state.osVersion = report?.osVersion
        if let expectedIdentity, report?.identity == expectedIdentity {
            confirmationTask?.cancel()
            confirmationTask = nil
            self.expectedIdentity = nil
            state.phase = .succeeded
            state.errorMessage = nil
        } else if state.phase == .failed, let identity = report?.identity, identity == state.target {
            state.phase = .idle
            state.errorMessage = nil
        }
    }

    func receiveSystemInformation(_ information: GuestSystemInformation) {
        state.osVersion = information.osVersion
        state.reportedBuild = information.guestAppBuild.flatMap(Int.init)
    }

    func update(makeImage: @escaping @Sendable () async throws -> (URL, GuestAppUpdatePackage)) {
        guard isHost, state.canUpdate, let token = session else { return }
        let id = UUID()
        operation = id
        state.phase = .preparing
        state.errorMessage = nil
        updateTask = schedule {
            defer { if self.operation == id { self.updateTask = nil } }
            do {
                let (url, package) = try await makeImage()
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                try self.requireSession(token)
                guard package.identity == self.state.target else { throw GuestAppUpdateError.invalidPackage }
                self.package = package
                let reply = try await self.connection.request(
                    BeginGuestAppUpdate(session: token, operation: id, package: package),
                    reply: GuestAppUpdateReply.self, timeout: self.requestTimeout)
                try self.requireSession(token)
                if case .failure(let message) = reply { throw GuestSessionError.remote(message) }
                self.state.phase = .transferring
                try await self.connection.sendFile(at: url, metadata: TransferIdentity(session: token, operation: id, purpose: .appUpdate).metadata)
                try self.requireSession(token)
                if self.state.phase == .transferring { self.state.phase = .installing }
            } catch {
                if self.operation == id && self.expectedIdentity == nil { self.fail(error.localizedDescription) }
            }
        }
        // Includes transfer and staging: a guest disappearing mid-operation must not leave a spinner forever.
        startDeadline()
    }

    private func startDeadline() {
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            do { try await Task.sleep(for: self?.confirmationTimeout ?? .seconds(180)) } catch { return }
            guard let self, self.state.isBusy else { return }
            self.expectedIdentity = nil
            self.fail(GuestAppUpdateError.confirmationTimedOut.localizedDescription)
        }
    }

    private func begin(_ request: GuestRequest<BeginGuestAppUpdate, GuestAppUpdateReply>) {
        guard !isHost, isConnected, request.payload.session == session else { return }
        let value = request.payload
        let valid = context.hostCapabilities.contains(Self.capability) && prepareInstallation != nil &&
            value.package.byteCount > 0 && value.package.byteCount <= GuestAppUpdatePackage.maximumBytes &&
            value.package.sha256.count == SHA256.Digest.byteCount &&
            report.map { value.package.identity.supports(osVersion: $0.osVersion) && value.package.identity.isUpdate(over: $0.identity) } == true
        schedule {
            guard valid else { try await request.reply(.failure(GuestAppUpdateError.unsupported.localizedDescription)); return }
            guard self.operation == nil else { try await request.reply(.failure(GuestAppUpdateError.busy.localizedDescription)); return }
            self.operation = value.operation
            self.package = value.package
            try await request.reply(.accepted)
            self.schedule {
                try await Task.sleep(for: .seconds(180))
                try self.requireSession(value.session)
                if self.operation == value.operation && !self.committed { self.clearPendingInstallation() }
            }
        }
    }

    override func receiveOffer(_ offer: GuestFileOffer, metadata: TransferIdentity) {
        guard !isHost, metadata.session == session, metadata.operation == operation,
              let package, let prepareInstallation, !receiving, prepared == nil else {
            schedule { await offer.reject() }
            return
        }
        guard offer.byteCount == package.byteCount else {
            clearPendingInstallation()
            schedule { await offer.reject() }
            return
        }
        receiving = true
        receiveTask = schedule {
            defer { if self.operation == metadata.operation { self.receiveTask = nil } }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dmg")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                try await offer.receive(url)
                try self.requireSession(metadata.session)
                guard self.operation == metadata.operation else { throw GuestAppUpdateError.interrupted }
                try await GuestUpdateFiles.verify(url, package: package)
                let prepared = try await prepareInstallation(url, package)
                do {
                    try self.requireSession(metadata.session)
                    guard self.operation == metadata.operation else { throw GuestAppUpdateError.interrupted }
                } catch { prepared.discard(); throw error }
                self.prepared = prepared
                self.receiving = false
                try await self.connection.send(GuestAppUpdateProgress(session: metadata.session, operation: metadata.operation, error: nil))
            } catch {
                if self.session == metadata.session && self.operation == metadata.operation {
                    // This task still owns delivery of the failure response.
                    self.receiveTask = nil
                    self.clearPendingInstallation()
                    try? await self.connection.send(GuestAppUpdateProgress(session: metadata.session, operation: metadata.operation, error: error.localizedDescription))
                }
            }
        }
    }

    private func receive(_ update: GuestAppUpdateProgress) {
        guard isHost, update.session == session, update.operation == operation, state.isBusy else { return }
        if let error = update.error { fail(error); return }
        guard let package, expectedIdentity == nil else { return }
        expectedIdentity = package.identity
        state.phase = .reconnecting
        startDeadline()
        schedule {
            do {
                let reply = try await self.connection.request(CommitGuestAppUpdate(session: update.session, operation: update.operation),
                                                              reply: GuestAppUpdateReply.self, timeout: self.requestTimeout)
                if case .failure(let message) = reply {
                    self.expectedIdentity = nil
                    self.fail(message)
                }
            } catch {
                // A lost acknowledgement can mean the old app has already exited.
                // Only a new connection with the exact identity confirms success.
                self.log(error)
            }
        }
    }

    private func commit(_ request: GuestRequest<CommitGuestAppUpdate, GuestAppUpdateReply>) {
        guard !isHost, request.payload.session == session, request.payload.operation == operation,
              let prepared, !committed, !committing else { return }
        committing = true
        schedule {
            do {
                try self.requireSession(request.payload.session)
                try await prepared.launchInstaller()
            } catch {
                self.clearPendingInstallation()
                try? await request.reply(.failure(error.localizedDescription))
                return
            }
            self.committed = true
            // After handing off to the installer, a lost acknowledgement must
            // not leave the old app running. The host confirms by reconnection.
            try? await request.reply(.accepted)
            prepared.terminateApp()
        }
    }

    private func cancel(_ message: CancelGuestAppUpdate) {
        guard !isHost, message.session == session, message.operation == operation, !committed else { return }
        clearPendingInstallation()
    }

    private func clearPendingInstallation() {
        receiveTask?.cancel()
        receiveTask = nil
        if !committed { prepared?.discard() }
        prepared = nil
        operation = nil
        package = nil
        receiving = false
        committing = false
    }

    private func fail(_ message: String) {
        if isHost, let token = session, let operation {
            schedule {
                try self.requireSession(token)
                try await self.connection.send(CancelGuestAppUpdate(session: token, operation: operation))
            }
        }
        updateTask?.cancel()
        updateTask = nil
        expectedIdentity = nil
        state.phase = .failed
        state.errorMessage = message
        operation = nil
        package = nil
        confirmationTask?.cancel()
        confirmationTask = nil
    }

    override func invalidate() {
        super.invalidate()
        state.isConnected = false
        state.supportsRemoteUpdate = false
        state.installed = nil
        state.reportedBuild = nil
        state.osVersion = nil
        if isHost {
            if expectedIdentity == nil {
                if state.isBusy { fail(GuestAppUpdateError.interrupted.localizedDescription) }
                confirmationTask?.cancel()
            }
            operation = nil
            package = nil
        } else {
            clearPendingInstallation()
            committed = false
        }
    }

    deinit { confirmationTask?.cancel(); updateTask?.cancel(); receiveTask?.cancel() }
}
