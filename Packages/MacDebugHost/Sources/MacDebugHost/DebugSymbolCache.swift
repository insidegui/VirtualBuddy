import Foundation
import MacDebugProtocol
import Combine
import Security

@MainActor
public final class DebugSymbolCache: ObservableObject {
    public struct Entry: Identifiable, Codable {
        public let id: String
        public let system: String
        public let bytes: Int64
    }
    public struct Activity: Identifiable {
        public let id: UUID
        public let system: String
        public var detail: String
        public var fraction: Double
    }
    @Published public private(set) var activities: [Activity] = []
    @Published public private(set) var entries: [Entry] = []
    @Published private var leases: [UUID: String] = [:]
    private var builders: Set<String> = []
    private var cancellations: [UUID: () -> Void] = [:]
    private let root: URL
    private let helperURL: URL

    public init(root: URL, helperURL: URL) {
        self.root = root
        self.helperURL = helperURL
        reload()
    }

    public func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        entries = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("complete.json")),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.id == url.lastPathComponent else { return nil }
            return entry
        }.sorted { $0.system.localizedStandardCompare($1.system) == .orderedDescending }
    }

    public func isInUse(_ entry: Entry) -> Bool { leases.values.contains(entry.id) }
    public func remove(_ entry: Entry) throws {
        guard entries.contains(where: { $0.id == entry.id }), !isInUse(entry) else { throw MacDebugError("These symbols are in use.") }
        try FileManager.default.removeItem(at: root.appendingPathComponent(entry.id))
        reload()
    }
    public func cancel(_ run: UUID) { cancellations[run]?() }
    public func release(_ run: UUID) { leases[run] = nil }

    public func acquire(_ images: DebugSystemImages, session: any RemoteDebugSession, run: UUID, developer: URL, cancel: @escaping () -> Void) async throws -> URL {
        try images.validate()
        let key = "\(images.build)-\(images.architecture)-\(images.uuid.uuidString)"
        leases[run] = key
        let system = "\(images.version) (\(images.build))"
        let destination = root.appendingPathComponent(key)
        let support = destination.appendingPathComponent("DeviceSupport")
        while builders.contains(key) { try await Task.sleep(for: .milliseconds(200)) }
        let fm = FileManager.default
        let cachedLib = support.appendingPathComponent("\(system)/Symbols/usr/lib")
        if let marker = try? Data(contentsOf: destination.appendingPathComponent("complete.json")),
           let entry = try? JSONDecoder().decode(Entry.self, from: marker), entry.id == key,
           fm.fileExists(atPath: cachedLib.appendingPathComponent("dyld").path),
           fm.fileExists(atPath: cachedLib.appendingPathComponent("libSystem.B.dylib").path) { return support }
        builders.insert(key)
        defer {
            builders.remove(key)
            activities.removeAll { $0.id == run }
            cancellations.removeValue(forKey: run)
        }
        cancellations[run] = cancel
        activities.append(.init(id: run, system: system, detail: "Preparing system images", fraction: 0))
        func update(_ detail: String, _ fraction: Double) {
            guard let i = activities.firstIndex(where: { $0.id == run }) else { return }
            activities[i].detail = detail
            activities[i].fraction = fraction
        }

        let work = root.appendingPathComponent(".building-" + run.uuidString)
        let raw = work.appendingPathComponent("raw")
        let symbols = work.appendingPathComponent("DeviceSupport/\(system)/Symbols")
        try DebugTools.directory(raw)
        defer { try? fm.removeItem(at: work) }
        try DebugTools.directory(symbols)
        let total = images.files.reduce(Int64(0)) { $0 + $1.bytes }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let available, available < total * 3 { throw MacDebugError("Free at least \(ByteCountFormatter.string(fromByteCount: total * 3, countStyle: .file)) to prepare these macOS symbols.") }

        var received: Int64 = 0
        for file in images.files {
            let output = raw.appendingPathComponent(file.name)
            update("Copying " + file.name, 0.7 * Double(received) / Double(total))
            try await session.transferDebugImage(file, run: run, to: output)
            guard try output.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(file.bytes) else {
                throw MacDebugError("Incomplete transfer of \(file.name).")
            }
            received += file.bytes
        }
        let primary = raw.appendingPathComponent(images.primary)
        let handle = try FileHandle(forReadingFrom: primary)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 104), header.count == 104, header.starts(with: Data("dyld_v1".utf8)),
              header.withUnsafeBytes({ UUID(uuid: $0.loadUnaligned(fromByteOffset: 88, as: uuid_t.self)) }) == images.uuid else {
            throw MacDebugError("The transferred cache does not match the target’s system image UUID.")
        }
        update("Extracting system libraries", 0.7)
        let extractor = developer.appendingPathComponent("Platforms/iPhoneOS.platform/usr/lib/dsc_extractor.bundle")
        let profile = "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath (param \"OUTPUT\")) (literal \"/dev/null\"))"
        // Sandbox path filters compare physical paths. Foundation can return
        // the /tmp alias even after resolving /private/tmp.
        guard let physicalPath = realpath(symbols.path, nil) else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let outputPath = String(cString: physicalPath)
        free(physicalPath)
        try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/sandbox-exec"), ["-D", "OUTPUT=" + outputPath, "-p", profile, helperURL.path, "extract", extractor.path, primary.path, outputPath])
        let lib = symbols.appendingPathComponent("usr/lib")
        guard lib.resolvingSymlinksInPath().standardizedFileURL.path == symbols.resolvingSymlinksInPath().appendingPathComponent("usr/lib").standardizedFileURL.path else {
            throw MacDebugError("The extracted system library directory is invalid.")
        }
        try DebugTools.directory(lib)
        // Some extractors also emit an image named dyld. LLDB needs the
        // standalone target loader, whose UUID can differ from that image.
        guard rename(raw.appendingPathComponent("dyld").path, lib.appendingPathComponent("dyld").path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try fm.removeItem(at: raw)
        guard fm.fileExists(atPath: lib.appendingPathComponent("libSystem.B.dylib").path) else { throw MacDebugError("Xcode could not extract the target’s system libraries.") }
        let size = try await Self.allocatedSize(of: symbols)
        let entry = Entry(id: key, system: system, bytes: size)
        try JSONEncoder().encode(entry).write(to: work.appendingPathComponent("complete.json"))
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: work)
        } else { try fm.moveItem(at: work, to: destination) }
        reload()
        return support
    }

    private nonisolated static func allocatedSize(of directory: URL) async throws -> Int64 {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileAllocatedSizeKey])
        var bytes: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            bytes += Int64(try file.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize ?? 0)
        }
        return bytes
    }

    /// Loaded only in the sandboxed extraction subprocess.
    public nonisolated static func extract(tool: URL, primary: URL, output: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(tool as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple and identifier \"com.apple.dsc_extractor\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess,
              let library = dlopen(tool.path, RTLD_LOCAL | RTLD_NOW) else { throw MacDebugError("This Xcode installation has no compatible Apple dyld cache extractor.") }
        defer { dlclose(library) }
        typealias Progress = @convention(block) (UInt32, UInt32) -> Void
        typealias Extract = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, Progress) -> Int32
        guard let symbol = dlsym(library, "dyld_shared_cache_extract_dylibs_progress"),
              unsafeBitCast(symbol, to: Extract.self)(primary.path, output.path, { _, _ in }) == 0 else { throw MacDebugError("Xcode could not extract this dyld cache.") }
    }
}
