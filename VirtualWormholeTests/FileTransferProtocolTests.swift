import XCTest
@testable import VirtualWormhole

final class FileTransferProtocolTests: XCTestCase {
    func testManifestAndEntryFramesRoundTrip() throws {
        let sessionID = UUID()
        let manifest = FileTransferManifest(sessionID: sessionID, rootPaths: ["Example.txt"])
        let entry = FileTransferEntry(
            relativePath: "Example.txt",
            kind: .regularFile,
            byteCount: 12,
            posixPermissions: 0o644,
            modificationDate: Date(timeIntervalSinceReferenceDate: 123)
        )
        let handle = try temporaryFileHandle()
        defer { try? handle.close() }

        try FileTransferProtocol.writeFrame(manifest, to: handle)
        try FileTransferProtocol.writeFrame(entry, to: handle)
        try FileTransferProtocol.writeEnd(to: handle)
        try handle.seek(toOffset: 0)

        XCTAssertEqual(
            try FileTransferProtocol.readFrame(FileTransferManifest.self, from: handle),
            manifest
        )
        XCTAssertEqual(
            try FileTransferProtocol.readFrame(FileTransferEntry.self, from: handle),
            entry
        )
        XCTAssertNil(try FileTransferProtocol.readFrame(FileTransferEntry.self, from: handle))
    }

    func testRelativePathValidationRejectsEscapes() {
        XCTAssertFalse(FileTransferPath.isValid(""))
        XCTAssertFalse(FileTransferPath.isValid("/tmp/file"))
        XCTAssertFalse(FileTransferPath.isValid("../file"))
        XCTAssertFalse(FileTransferPath.isValid("folder/../file"))
        XCTAssertFalse(FileTransferPath.isValid("folder//file"))
        XCTAssertFalse(FileTransferPath.isValid("folder/./file"))
        XCTAssertFalse(FileTransferPath.isValid("folder\0file"))
    }

    func testRelativePathValidationAcceptsNestedPaths() throws {
        let root = URL(filePath: "/tmp/VirtualBuddyFileTransferTest", directoryHint: .isDirectory)
        let destination = try FileTransferPath.destination(
            for: "Folder/Nested File.txt",
            under: root
        )

        XCTAssertEqual(destination.path, "/tmp/VirtualBuddyFileTransferTest/Folder/Nested File.txt")
    }

    private func temporaryFileHandle() throws -> FileHandle {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return try FileHandle(forUpdating: fileURL)
    }
}
