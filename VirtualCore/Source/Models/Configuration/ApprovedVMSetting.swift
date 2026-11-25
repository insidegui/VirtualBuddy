import CryptoKit
import Darwin
import Foundation

/// A review UI may show an untrusted candidate and explicitly approve the exact
/// value displayed. Runtime consumers use ApprovedVMSetting.approvedValue(in:).
public enum ApprovedSettingState<Value> {
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

extension ApprovedSettingState: Equatable where Value: Equatable {}

/// Where the host keeps the digest of the record it last approved for each bundle and setting.
struct SettingApprovals {
    var digest: (_ account: String) throws -> Data?
    var record: (_ digest: Data, _ account: String) throws -> Void

    static var keychain: Self {
        let store = HostSettingsApprovalStore()
        return Self(digest: store.digest(for:), record: store.record(_:for:))
    }
}

/// A setting that only takes effect once the host user has approved its exact value.
///
/// The value is one atomically replaced record per feature in .vbdata, which anyone who
/// can write to the bundle controls. The approval is a digest of that record kept by the
/// host, outside the bundle. It covers the virtual machine's identifier and is stored for
/// the bundle's location on disk, so it belongs to one virtual machine in one bundle on
/// this host. A record moved into another bundle, a bundle copied outside of VirtualBuddy
/// and a record that was since replaced all have to be reviewed again.
///
/// Use a stable, unique identifier for each setting and bump its schema for incompatible semantics.
struct ApprovedVMSetting<Value: Codable> {
    // A container also permits property lists to represent a scalar setting.
    private struct Payload: Codable {
        let value: Value
    }

    private struct Envelope: Codable {
        let version: Int
        let schema: UInt32
        let payload: Data
    }

    let identifier: String
    let schema: UInt32
    let validate: (Value) throws -> Void
    let approvals: SettingApprovals

    init(_ identifier: String, schema: UInt32, approvals: SettingApprovals = .keychain, validate: @escaping (Value) throws -> Void) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        precondition(!identifier.isEmpty && identifier.unicodeScalars.allSatisfy(allowed.contains))
        self.identifier = identifier
        self.schema = schema
        self.approvals = approvals
        self.validate = validate
    }

    var filename: String { "\(identifier).plist" }

    private func digest(of payload: Data, for vm: VBVirtualMachine) -> Data {
        var bytes = Data("VirtualBuddy.ApprovedVMSetting.v1\0\(identifier)\0".utf8)
        withUnsafeBytes(of: schema.bigEndian) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: vm.uuid.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(payload)
        return Data(SHA256.hash(data: bytes))
    }

    /// Names the bundle directory itself, which a copy made by any other means doesn't share.
    /// Renaming the bundle or moving it within its volume keeps the approval.
    private func approvalAccount(for vm: VBVirtualMachine) throws -> String {
        var info = stat()
        guard stat(vm.bundleURL.path, &info) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFDIR,
              let volume = try vm.bundleURL.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
            throw Failure("Settings that need approval require a virtual machine stored on a volume with a persistent identifier.")
        }
        return "\(identifier).\(volume).\(info.st_ino)"
    }

    private func readEnvelope(from vm: VBVirtualMachine) throws -> Envelope? {
        guard let data = try ApprovedSettingFile.read(filename, in: vm.metadataDirectoryURL) else { return nil }
        let envelope = try PropertyListDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.schema == schema else { throw Failure("Unsupported settings format.") }
        return envelope
    }

    private func isApproved(_ envelope: Envelope, in vm: VBVirtualMachine) throws -> Bool {
        try approvals.digest(approvalAccount(for: vm)) == digest(of: envelope.payload, for: vm)
    }

    private func validatedValue(_ envelope: Envelope) throws -> Value {
        let value = try PropertyListDecoder().decode(Payload.self, from: envelope.payload).value
        try validate(value)
        return value
    }

    /// Checks the approval before invoking the feature's decoder on a runtime path.
    func approvedValue(in vm: VBVirtualMachine) throws -> Value? {
        guard let envelope = try readEnvelope(from: vm), try isApproved(envelope, in: vm) else { return nil }
        return try validatedValue(envelope)
    }

    /// A setting used for review must be a passive data type, safe to decode from an untrusted bundle.
    func read(from vm: VBVirtualMachine) -> ApprovedSettingState<Value> {
        do {
            guard let envelope = try readEnvelope(from: vm) else { return .missing }
            let approved = try isApproved(envelope, in: vm)
            let value = try validatedValue(envelope)
            return approved ? .approved(value) : .needsApproval(value)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Only call for a value the host user approved. Reading never changes the bundle or the host's approvals.
    func approve(_ value: Value, in vm: VBVirtualMachine) throws {
        try validate(value)
        let account = try approvalAccount(for: vm)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(Payload(value: value))
        let data = try encoder.encode(Envelope(version: 1, schema: schema, payload: payload))
        try ApprovedSettingFile.write(data, named: filename, in: vm.metadataDirectoryURL)
        // Until this succeeds neither the previous record nor the new one is approved.
        try approvals.record(digest(of: payload, for: vm), account)
    }

    /// Gives a copy the approval its original has right now.
    /// Only call for a copy the host user made in VirtualBuddy. The value comes from
    /// the original's approved record, never from whatever the copy contains.
    func carryApproval(from original: VBVirtualMachine, to copy: VBVirtualMachine) throws {
        guard let value = try approvedValue(in: original) else { return }
        try approve(value, in: copy)
    }
}

/// Resolve records relative to an open directory. An imported bundle may contain
/// symlinks or special files in place of ordinary metadata.
private enum ApprovedSettingFile {
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
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= maxBytes else { throw Failure("Invalid settings file.") }
        let data = try file.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw Failure("Settings exceed the size limit.") }
        return data
    }

    static func write(_ data: Data, named name: String, in directory: URL) throws {
        guard data.count <= maxBytes else { throw Failure("Settings exceed the size limit.") }
        guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { throw posixError() }
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dir >= 0 else { throw posixError() }
        defer { close(dir) }
        let temporary = ".approved-settings-\(UUID().uuidString)"
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
