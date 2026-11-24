import Foundation
import MacDebugProtocol
import Combine
import Security
import os

@MainActor
public final class DebugSymbolCache: ObservableObject {
    public struct Entry: Identifiable, Codable {
        public let id: String
        public let system: String
        public let bytes: Int64
    }
    public struct Activity: Identifiable {
        public let id: UUID
        public let destinationID: UUID
        public let system: String
        public let detail: String
        public let fraction: Double?
    }
    @Published public private(set) var activities: [Activity] = []
    @Published public private(set) var entries: [Entry] = []
    @Published private var leases: [UUID: String] = [:]
    @Published private var removing: Set<String> = []
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
    public func isRemoving(_ entry: Entry) -> Bool { removing.contains(entry.id) }

    public func remove(_ entry: Entry) async throws {
        guard entries.contains(where: { $0.id == entry.id }), !isInUse(entry), removing.insert(entry.id).inserted else {
            throw MacDebugError("These symbols are in use.")
        }
        defer {
            removing.remove(entry.id)
            reload()
        }
        try await Self.deleteEntry(at: root.appendingPathComponent(entry.id))
    }

    private nonisolated static func deleteEntry(at directory: URL) async throws {
        let fm = FileManager.default
        let support = directory.appendingPathComponent("DeviceSupport")
        let retired = directory.appendingPathComponent(".deleting")
        // Retire the payload before recursive deletion. An interrupted deletion
        // keeps its list entry for retry and can never be mistaken for a cache hit.
        if fm.fileExists(atPath: support.path) { try fm.moveItem(at: support, to: retired) }
        if fm.fileExists(atPath: retired.path) { try fm.removeItem(at: retired) }
        try fm.removeItem(at: directory)
    }

    public func cancel(_ run: UUID) { cancellations[run]?() }
    public func release(_ run: UUID) { leases[run] = nil }

    public func acquire(_ images: DebugSystemImages, session: any RemoteDebugSession, destinationID: UUID, run: UUID, developer: URL, cancel: @escaping () -> Void) async throws -> URL {
        try images.validate()
        let key = "\(images.build)-\(images.architecture)-\(images.uuid.uuidString)"
        leases[run] = key
        let system = "\(images.version) (\(images.build))"
        let destination = root.appendingPathComponent(key)
        let support = destination.appendingPathComponent("DeviceSupport")
        while builders.contains(key) || removing.contains(key) { try await Task.sleep(for: .milliseconds(200)) }
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
        activities.append(.init(id: run, destinationID: destinationID, system: system, detail: "Preparing system images", fraction: 0))
        let work = root.appendingPathComponent(".building-" + run.uuidString)
        do {
            try await populate(work, system: system, images: images, session: session, run: run, developer: developer)
            try await Self.commit(work, to: destination, system: system)
        } catch {
            try? await Self.discard(work)
            throw error
        }
        reload()
        return support
    }

    private func populate(_ work: URL, system: String, images: DebugSystemImages, session: any RemoteDebugSession, run: UUID, developer: URL) async throws {
        func update(_ detail: String, _ fraction: Double?) {
            guard let i = activities.firstIndex(where: { $0.id == run }) else { return }
            let activity = activities[i]
            activities[i] = Activity(id: run, destinationID: activity.destinationID, system: system, detail: detail, fraction: fraction)
        }

        let raw = work.appendingPathComponent("raw")
        let symbols = work.appendingPathComponent("DeviceSupport/\(system)/Symbols")
        try DebugTools.directory(raw)
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
        update("Extracting system libraries", nil)
        let extractor = developer.appendingPathComponent("Platforms/iPhoneOS.platform/usr/lib/dsc_extractor.bundle")
        // Sandbox path filters compare physical paths. Foundation can return
        // the /tmp alias even after resolving /private/tmp.
        func physical(_ url: URL) throws -> String {
            guard let path = realpath(url.path, nil) else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { free(path) }
            return String(cString: path)
        }
        let outputPath = try physical(symbols), extractorPath = try physical(extractor)
        let parameters = ["OUTPUT": outputPath, "INPUT": try physical(raw), "EXTRACTOR": extractorPath,
                          "HELPER": try physical(helperURL), "CODE": try physical(Bundle.main.bundleURL)]
        let pipe = Pipe()
        // Run the helper by its own name: an app can ship it as a link to its main executable.
        let arguments = parameters.flatMap { ["-D", $0.key + "=" + $0.value] } +
            ["-p", Self.extractionSandbox, helperURL.path, "extract", extractorPath, primary.path, outputPath]
        async let extraction: Void = DebugTools.run(URL(fileURLWithPath: "/usr/bin/sandbox-exec"), arguments, standardOutput: pipe)
        for try await line in pipe.fileHandleForReading.bytes.lines {
            guard line.hasPrefix(Self.progressPrefix), let percent = Int(line.dropFirst(Self.progressPrefix.count)),
                  (0...100).contains(percent) else { continue }
            update("Extracting system libraries (\(percent)%)", 0.7 + 0.3 * Double(percent) / 100)
        }
        try await extraction
        update("Finalizing symbol cache", nil)
    }

    /// The extractor parses images supplied by the target, in a process that carries this
    /// app's code identity. It may read only the code it runs and its input, write only its
    /// output, and reach no other process, so a parsing flaw cannot use the app's access to
    /// the user's files, Keychain or network.
    private nonisolated static let extractionSandbox = """
        (version 1)
        (deny default)
        (import "system.sb")
        (deny mach-lookup (xpc-service-name-prefix ""))
        (allow process-exec (literal (param "HELPER")))
        (allow file-read* file-map-executable
            (literal (param "HELPER")) (literal (param "EXTRACTOR")) (subpath (param "CODE")))
        (allow file-read* (subpath (param "INPUT")) (subpath (param "OUTPUT")))
        (allow file-write* (subpath (param "OUTPUT")))
        """

    /// The extractor's output goes to the debugger. Accept only plain files and
    /// directories, so nothing in the tree can stand in for a file outside it.
    nonisolated static func requirePlainTree(_ directory: URL) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var failure: Error?
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) { _, error in
            failure = error
            return false
        }
        while let entry = entries?.nextObject() as? URL {
            try Task.checkCancellation()
            let type = try entry.resourceValues(forKeys: keys)
            guard type.isSymbolicLink != true, type.isRegularFile == true || type.isDirectory == true else {
                throw MacDebugError("The extracted system libraries contain an unexpected item.")
            }
        }
        if let failure { throw failure }
    }

    private nonisolated static func discard(_ work: URL) async throws {
        try FileManager.default.removeItem(at: work)
    }

    // Directory enumeration, removing the raw images and replacing a previous
    // cache can all take seconds. Keep the whole commit off the main actor.
    private nonisolated static func commit(_ work: URL, to destination: URL, system: String) async throws {
        let fm = FileManager.default
        let raw = work.appendingPathComponent("raw")
        let symbols = work.appendingPathComponent("DeviceSupport/\(system)/Symbols")
        let lib = symbols.appendingPathComponent("usr/lib")
        try requirePlainTree(symbols)
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
        let size = try allocatedSize(of: symbols)
        let entry = Entry(id: destination.lastPathComponent, system: system, bytes: size)
        try JSONEncoder().encode(entry).write(to: work.appendingPathComponent("complete.json"))
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: work)
        } else { try fm.moveItem(at: work, to: destination) }
    }

    private nonisolated static func allocatedSize(of directory: URL) throws -> Int64 {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileAllocatedSizeKey])
        var bytes: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            bytes += Int64(try file.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize ?? 0)
        }
        return bytes
    }

    private nonisolated static let progressPrefix = "mac-debug-progress "

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
        let lastPercent = OSAllocatedUnfairLock(initialState: -1)
        let progress: Progress = { current, total in
            guard total > 0 else { return }
            let percent = Int(UInt64(min(current, total)) * 100 / UInt64(total))
            lastPercent.withLock {
                guard percent > $0 else { return }
                $0 = percent
                try? FileHandle.standardOutput.write(contentsOf: Data("\(progressPrefix)\(percent)\n".utf8))
            }
        }
        guard let symbol = dlsym(library, "dyld_shared_cache_extract_dylibs_progress"),
              unsafeBitCast(symbol, to: Extract.self)(primary.path, output.path, progress) == 0 else { throw MacDebugError("Xcode could not extract this dyld cache.") }
    }
}
