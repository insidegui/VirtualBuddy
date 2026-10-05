import Foundation
import Darwin

/// The file operations used by saved session transactions.
///
/// Every mutation goes through this protocol so that tests can fail or interrupt the transaction at any step.
protocol SavedSessionFileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    func byteCount(of url: URL) -> UInt64?
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func read(_ url: URL) throws -> Data

    func createDirectory(_ url: URL) throws
    /// Copies a file or directory, cloning it when the volume supports it.
    func copy(from source: URL, to destination: URL) throws
    /// Creates a copy-on-write clone. Fails instead of falling back to a full copy.
    func clone(from source: URL, to destination: URL) throws
    /// Atomically moves an item. When `replacingExisting` is `false` and the destination exists, this fails.
    func move(from source: URL, to destination: URL, replacingExisting: Bool) throws
    func remove(_ url: URL) throws
    /// Writes the data so that it's on stable storage by the time this returns.
    func writeDurably(_ data: Data, to url: URL) throws
    /// Makes sure the directory entries of the directory are on stable storage.
    func synchronizeDirectory(_ url: URL) throws
    /// Makes sure the contents of the file are on stable storage.
    func synchronizeFile(_ url: URL) throws
}

struct DefaultSavedSessionFileSystem: SavedSessionFileSystem {
    func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    func byteCount(of url: URL) -> UInt64? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return UInt64(info.st_size)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
    }

    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func copy(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func clone(from source: URL, to destination: URL) throws {
        guard clonefile(source.path, destination.path, 0) == 0 else {
            throw SavedSessionError(posix: errno, operation: "clone", url: source)
        }
    }

    func move(from source: URL, to destination: URL, replacingExisting: Bool) throws {
        let result: Int32
        if replacingExisting {
            result = rename(source.path, destination.path)
        } else {
            result = renamex_np(source.path, destination.path, UInt32(RENAME_EXCL))
        }
        guard result == 0 else {
            throw SavedSessionError(posix: errno, operation: "move", url: destination)
        }
    }

    func remove(_ url: URL) throws {
        guard exists(url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func writeDurably(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try synchronizeFile(url)
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    func synchronizeDirectory(_ url: URL) throws {
        try synchronize(path: url.path, directory: true)
    }

    func synchronizeFile(_ url: URL) throws {
        try synchronize(path: url.path, directory: false)
    }

    private func synchronize(path: String, directory: Bool) throws {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else {
            throw SavedSessionError(posix: errno, operation: "open", url: URL(fileURLWithPath: path))
        }
        defer { close(descriptor) }

        /// F_FULLFSYNC asks the drive to flush its cache, which a plain fsync doesn't guarantee on macOS.
        /// Not every filesystem implements it, so fall back to fsync.
        if fcntl(descriptor, F_FULLFSYNC) != 0 {
            guard fsync(descriptor) == 0 else {
                throw SavedSessionError(posix: errno, operation: "sync", url: URL(fileURLWithPath: path))
            }
        }
    }
}

extension SavedSessionError {
    init(posix code: Int32, operation: String, url: URL) {
        switch code {
        case ENOSPC, EDQUOT:
            self = .diskFull
        case ENOTSUP, EXDEV:
            self = .cloneUnsupported(url)
        default:
            self = .io(operation: operation, path: url.lastPathComponent, code: code)
        }
    }
}
