import CryptoKit
import Darwin
import Foundation

/// A review UI may show an untrusted candidate and explicitly approve the exact
/// value displayed. Runtime consumers use SignedVMSetting.approvedValue(in:).
public enum SignedSettingState<Value> {
    case missing
    case approved(Value)
    case needsApproval(Value)
    case unavailable(String)

    public var approvedValue: Value? {
        if case .approved(let value) = self { return value }
        return nil
    }
    public var reviewValue: Value? {
        switch self {
        case .approved(let value), .needsApproval(let value): return value
        case .missing, .unavailable: return nil
        }
    }
}

extension SignedSettingState: Equatable where Value: Equatable {}

/// Where the host keeps the digest of the record it last approved for each bundle and setting.
struct SignedSettingApprovals {
    var digest: (_ account: String) throws -> Data?
    var record: (_ digest: Data, _ account: String) throws -> Void

    static var keychain: Self {
        let store = HostSettingsApprovalStore()
        return Self(digest: store.digest(for:), record: store.record(_:for:))
    }
}

/// One atomically replaced record per feature in .vbdata. Use a stable, unique
/// identifier for each setting and bump its schema for incompatible semantics.
///
/// An approval belongs to one virtual machine in one bundle on this host. The signature
/// covers the virtual machine's identifier, and the host separately remembers the latest
/// record it approved for the bundle's location on disk. A record moved into another
/// bundle, a bundle copied outside of VirtualBuddy and a record that was since replaced
/// all have to be reviewed again.
struct SignedVMSetting<Value: Codable> {
    // A container also permits property lists to represent a scalar setting.
    private struct Payload: Codable {
        let value: Value
    }

    private struct Envelope: Codable {
        let version: Int
        let schema: UInt32
        let payload: Data
        let signature: Data?
    }

    let identifier: String
    let schema: UInt32
    let validate: (Value) throws -> Void
    let key: (HostSettingsSigningKey.Access) throws -> P256.Signing.PrivateKey?
    let approvals: SignedSettingApprovals

    init(_ identifier: String, schema: UInt32, key: @escaping (HostSettingsSigningKey.Access) throws -> P256.Signing.PrivateKey? = HostSettingsSigningKey().key,
         approvals: SignedSettingApprovals = .keychain, validate: @escaping (Value) throws -> Void) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        precondition(!identifier.isEmpty && identifier.unicodeScalars.allSatisfy(allowed.contains))
        self.identifier = identifier
        self.schema = schema
        self.key = key
        self.approvals = approvals
        self.validate = validate
    }

    var filename: String { "\(identifier).signed.plist" }

    private func signedBytes(_ payload: Data, for vm: VBVirtualMachine) -> Data {
        var bytes = Data("VirtualBuddy.SignedVMSetting.v1\0\(identifier)\0".utf8)
        withUnsafeBytes(of: schema.bigEndian) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: vm.uuid.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(payload)
        return bytes
    }

    /// Names the bundle directory itself, which a copy made by any other means doesn't share.
    /// Renaming the bundle or moving it within its volume keeps the approval.
    private func approvalAccount(for vm: VBVirtualMachine) throws -> String {
        var info = stat()
        guard stat(vm.bundleURL.path, &info) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFDIR,
              let volume = try vm.bundleURL.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
            throw Failure("Signed settings require a virtual machine stored on a volume with a persistent identifier.")
        }
        return "\(identifier).\(volume).\(info.st_ino)"
    }

    private func readEnvelope(from vm: VBVirtualMachine) throws -> Envelope? {
        guard let data = try SignedSettingFile.read(filename, in: vm.metadataDirectoryURL) else { return nil }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.schema == schema else { throw Failure("Unsupported signed settings format.") }
        return envelope
    }

    private func isApproved(_ envelope: Envelope, in vm: VBVirtualMachine) throws -> Bool {
        guard let bytes = envelope.signature, let signature = try? P256.Signing.ECDSASignature(rawRepresentation: bytes),
              let localKey = try key(.verify) else { return false }
        let signed = signedBytes(envelope.payload, for: vm)
        guard localKey.publicKey.isValidSignature(signature, for: signed) else { return false }
        return try approvals.digest(approvalAccount(for: vm)) == Data(SHA256.hash(data: signed))
    }

    private func validatedValue(_ envelope: Envelope) throws -> Value {
        let value = try PropertyListDecoder().decode(Payload.self, from: envelope.payload).value
        try validate(value)
        return value
    }

    /// Verify before invoking the feature's decoder on a runtime path.
    func approvedValue(in vm: VBVirtualMachine) throws -> Value? {
        guard let envelope = try readEnvelope(from: vm), try isApproved(envelope, in: vm) else { return nil }
        return try validatedValue(envelope)
    }

    /// A setting used for review must be a passive data type, safe to decode from an untrusted bundle.
    func read(from vm: VBVirtualMachine) -> SignedSettingState<Value> {
        do {
            guard let envelope = try readEnvelope(from: vm) else { return .missing }
            let approved = try isApproved(envelope, in: vm)
            let value = try validatedValue(envelope)
            return approved ? .approved(value) : .needsApproval(value)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Only call for a host-approved value. Verification never creates a key or modifies the bundle.
    func approve(_ value: Value, in vm: VBVirtualMachine) throws {
        try validate(value)
        let account = try approvalAccount(for: vm)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(Payload(value: value))
        guard let key = try key(.sign) else { throw Failure("The host settings signing key is unavailable.") }
        let signed = signedBytes(payload, for: vm)
        let signature = try key.signature(for: signed)
        let data = try encoder.encode(Envelope(version: 1, schema: schema, payload: payload, signature: signature.rawRepresentation))
        try SignedSettingFile.write(data, named: filename, in: vm.metadataDirectoryURL)
        // Until this succeeds neither the previous record nor the new one is approved.
        try approvals.record(Data(SHA256.hash(data: signed)), account)
    }

    /// Gives a copy the approval its original has right now, signed again for the copy.
    /// Only call for a copy the host user made in VirtualBuddy. The value comes from
    /// the original's verified record, never from whatever the copy contains.
    func carryApproval(from original: VBVirtualMachine, to copy: VBVirtualMachine) throws {
        guard let value = try approvedValue(in: original) else { return }
        try approve(value, in: copy)
    }
}

/// Resolve records relative to an open directory. An imported bundle may contain
/// symlinks or special files in place of ordinary metadata.
private enum SignedSettingFile {
    static let maxBytes = 1 << 20

    static func read(_ name: String, in directory: URL) throws -> Data? {
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if dir == -1 && errno == ENOENT { return nil }
        guard dir >= 0 else { throw posixError() }
        defer { close(dir) }
        let fd = openat(dir, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd == -1 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= maxBytes else { throw Failure("Invalid signed settings file.") }
        let data = try file.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw Failure("Signed settings exceed the size limit.") }
        return data
    }

    static func write(_ data: Data, named name: String, in directory: URL) throws {
        guard data.count <= maxBytes else { throw Failure("Signed settings exceed the size limit.") }
        guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { throw posixError() }
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw posixError() }
        defer { close(dir) }
        let temporary = ".signed-settings-\(UUID().uuidString)"
        let fd = openat(dir, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        defer { unlinkat(dir, temporary, 0) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try file.write(contentsOf: data)
        try file.close()
        guard renameat(dir, temporary, dir, name) == 0 else { throw posixError() }
    }

    private static func posixError() -> POSIXError { POSIXError(.init(rawValue: errno) ?? .EIO) }
}
