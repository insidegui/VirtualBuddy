import XCTest
@testable import VirtualCore

@available(macOS 13, *)
final class VirtualMachineCreationTests: XCTestCase {
    private var creators: [(URL) throws -> VBVirtualMachine] {
        [
            { try VBVirtualMachine(bundleURL: $0, isNewInstall: true) },
            { try VBVirtualMachine(creatingLinuxMachineAt: $0) }
        ]
    }

    func testNewInstallationPreservesExistingVirtualMachine() throws {
        for create in creators {
            let url = try temporaryBundleURL()
            var existing = try VBVirtualMachine(bundleURL: url, isNewInstall: true)
            existing.metadata.installFinished = true
            existing.installRestoreData = Data("existing installation".utf8)
            try existing.saveMetadata()

            let diskURL = url.appendingPathComponent("Disk.img")
            let diskData = Data("existing disk contents".utf8)
            try diskData.write(to: diskURL)
            let metadataURLs = ["Config.plist", "Metadata.plist", "Install.plist"].map {
                existing.metadataDirectoryURL.appendingPathComponent($0)
            }
            let savedMetadata = try metadataURLs.map { try Data(contentsOf: $0) }

            assertCollision(at: url, create: create)

            XCTAssertEqual(try Data(contentsOf: diskURL), diskData)
            XCTAssertEqual(try metadataURLs.map { try Data(contentsOf: $0) }, savedMetadata)
            let reopened = try VBVirtualMachine(bundleURL: url, createIfNeeded: false)
            XCTAssertEqual(reopened.uuid, existing.uuid)
            XCTAssertTrue(reopened.metadata.installFinished)
        }
    }

    func testNewInstallationRejectsExistingFile() throws {
        for create in creators {
            let url = try temporaryBundleURL()
            let contents = Data("existing file".utf8)
            try contents.write(to: url)

            assertCollision(at: url, create: create)

            XCTAssertEqual(try Data(contentsOf: url), contents)
        }
    }

    func testNewInstallationRejectsEmptyBundleDirectory() throws {
        for create in creators {
            let url = try temporaryBundleURL()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

            assertCollision(at: url, create: create)

            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
        }
    }

    func testNewInstallationRejectsSymbolicLinks() throws {
        for create in creators {
            for targetExists in [true, false] {
                let url = try temporaryBundleURL()
                let target = url.deletingLastPathComponent().appendingPathComponent("Target")
                if targetExists {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                }
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)

                assertCollision(at: url, create: create)

                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
                if targetExists {
                    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
                } else {
                    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
                }
            }
        }
    }

    func testNewInstallationCreatesUnusedDestinationAndCanBeReopened() throws {
        for create in creators {
            let url = try temporaryBundleURL()
            let vm = try create(url)
            try vm.saveMetadata()

            let reopened = try VBVirtualMachine(bundleURL: url, createIfNeeded: false)
            XCTAssertEqual(reopened.uuid, vm.uuid)
            XCTAssertEqual(reopened.configuration.systemType, vm.configuration.systemType)
            XCTAssertFalse(reopened.metadata.installFinished)
        }
    }

    func testNewBundleHasNoGroupOrOtherPermissions() throws {
        for create in creators {
            let url = try temporaryBundleURL()
            _ = try create(url)

            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
            XCTAssertEqual(permissions & 0o077, 0)
        }
    }

    private func assertCollision(
        at url: URL,
        create: (URL) throws -> VBVirtualMachine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try create(url), file: file, line: line) { error in
            XCTAssertTrue(error is VBVirtualMachine.BundleAlreadyExistsError, file: file, line: line)
        }
    }

    private func temporaryBundleURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("Test VM").appendingPathExtension(VBVirtualMachine.bundleExtension)
    }
}
