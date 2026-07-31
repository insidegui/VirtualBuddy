//
//  VBDiskResizerTests.swift
//  VirtualWormholeTests
//

import XCTest
@testable import VirtualCore
import zlib

final class VBDiskResizerTests: XCTestCase {

    func testBlankRawDiskGrowsWithoutParsingInvalidGPT() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: 1024).write(to: url)

        try await VBDiskResizer.resizeDiskImage(at: url, format: .raw, newSize: 2048)

        XCTAssertEqual(try fileSize(at: url), 2048)
    }

    func testRawGrowthDoesNotRequireLogicalSizeInFreeSpace() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: 1024).write(to: url)

        let values = try url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey])
        let available = UInt64(values.volumeAvailableCapacity ?? 0)
        let newSize = ((available + 1024) / 512 + 1) * 512

        try await VBDiskResizer.resizeDiskImage(at: url, format: .raw, newSize: newSize)

        XCTAssertEqual(try fileSize(at: url), newSize)
    }

    func testFailedRawResizeLeavesOriginalImageUntouched() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data(repeating: 0xA5, count: 1024)
        try original.write(to: url)

        do {
            try await VBDiskResizer.resizeDiskImage(at: url, format: .raw, newSize: 1537)
            XCTFail("Expected an unaligned resize to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testEqualSizeRetryPreservesOverlappingRecoveryMove() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let sectorSize = 512
        let recoverySectors = 16_384
        let oldTotalSectors = 32_768
        let growthSectors = 4_096
        let oldLastUsable = oldTotalSectors - 41
        let oldRecoveryFirst = oldLastUsable - recoverySectors + 1
        let newRecoveryFirst = oldRecoveryFirst + growthSectors
        var image = makeGPTImage(
            totalSectors: oldTotalSectors,
            mainLast: oldRecoveryFirst - 1,
            recoveryFirst: oldRecoveryFirst,
            recoveryLast: oldLastUsable
        )
        image.append(Data(count: growthSectors * sectorSize))
        try image.write(to: url)
        let newSize = UInt64((oldTotalSectors + growthSectors) * sectorSize)
        XCTAssertEqual(try fileSize(at: url), newSize)

        var originalRecovery = Data(count: recoverySectors * sectorSize)
        originalRecovery.withUnsafeMutableBytes { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index % 251)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(oldRecoveryFirst * sectorSize))
        try handle.write(contentsOf: originalRecovery)
        try handle.close()

        try await VBDiskResizer.resizeDiskImage(
            at: url,
            format: .raw,
            newSize: newSize
        )

        XCTAssertEqual(
            try read(url, offset: newRecoveryFirst * sectorSize, count: originalRecovery.count),
            originalRecovery
        )
        XCTAssertEqual(
            try read(url, offset: oldRecoveryFirst * sectorSize, count: growthSectors * sectorSize),
            Data(count: growthSectors * sectorSize)
        )
    }

    func testNonOverlappingRecoveryMoveClearsOldRange() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let sectorSize = 512
        let recoverySectors = 64
        let oldTotalSectors = 1_024
        let growthSectors = 128
        let oldLastUsable = oldTotalSectors - 41
        let oldRecoveryFirst = oldLastUsable - recoverySectors + 1
        let newRecoveryFirst = oldRecoveryFirst + growthSectors
        try makeGPTImage(
            totalSectors: oldTotalSectors,
            mainLast: oldRecoveryFirst - 1,
            recoveryFirst: oldRecoveryFirst,
            recoveryLast: oldLastUsable
        ).write(to: url)
        let originalRecovery = Data(repeating: 0xA5, count: recoverySectors * sectorSize)
        try write(originalRecovery, to: url, offset: oldRecoveryFirst * sectorSize)

        try await VBDiskResizer.resizeDiskImage(
            at: url,
            format: .raw,
            newSize: UInt64((oldTotalSectors + growthSectors) * sectorSize)
        )

        XCTAssertEqual(
            try read(url, offset: newRecoveryFirst * sectorSize, count: originalRecovery.count),
            originalRecovery
        )
        XCTAssertEqual(
            try read(url, offset: oldRecoveryFirst * sectorSize, count: originalRecovery.count),
            Data(count: originalRecovery.count)
        )
    }

    func testCorruptGPTHeaderIsIgnored() async throws {
        try await assertCorruptGPTIsIgnored(at: 512 + 56)
    }

    func testCorruptPartitionEntriesAreIgnored() async throws {
        try await assertCorruptGPTIsIgnored(at: 2 * 512 + 120)
    }

    func testOversizedPartitionEntryArrayDoesNotCrossDiskEnd() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let oldTotalSectors = 1_024
        let newTotalSectors = 1_152
        let oldLastUsable = oldTotalSectors - 41
        let recoveryFirst = oldLastUsable - 64 + 1
        try makeGPTImage(
            totalSectors: oldTotalSectors,
            mainLast: recoveryFirst - 1,
            recoveryFirst: recoveryFirst,
            recoveryLast: oldLastUsable,
            entryCount: 129
        ).write(to: url)

        try await VBDiskResizer.resizeDiskImage(
            at: url,
            format: .raw,
            newSize: UInt64(newTotalSectors * 512)
        )

        XCTAssertEqual(try fileSize(at: url), UInt64(newTotalSectors * 512))
        XCTAssertEqual(
            try read(url, offset: (newTotalSectors - 1) * 512, count: 512),
            Data(count: 512)
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? UInt64)
    }

    private func read(_ url: URL, offset: Int, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try XCTUnwrap(handle.read(upToCount: count))
    }

    private func write(_ data: Data, to url: URL, offset: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
    }

    private func assertCorruptGPTIsIgnored(at corruptionOffset: Int) async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let oldTotalSectors = 1_024
        let growthSectors = 128
        let oldLastUsable = oldTotalSectors - 41
        let recoveryFirst = oldLastUsable - 64 + 1
        var image = makeGPTImage(
            totalSectors: oldTotalSectors,
            mainLast: recoveryFirst - 1,
            recoveryFirst: recoveryFirst,
            recoveryLast: oldLastUsable
        )
        image[corruptionOffset] ^= 1
        try image.write(to: url)
        let originalRecovery = Data(repeating: 0xA5, count: 64 * 512)
        try write(originalRecovery, to: url, offset: recoveryFirst * 512)

        try await VBDiskResizer.resizeDiskImage(
            at: url,
            format: .raw,
            newSize: UInt64((oldTotalSectors + growthSectors) * 512)
        )

        XCTAssertEqual(
            try read(url, offset: recoveryFirst * 512, count: originalRecovery.count),
            originalRecovery
        )
    }

    private func makeGPTImage(
        totalSectors: Int,
        mainLast: Int,
        recoveryFirst: Int,
        recoveryLast: Int,
        entryCount: Int = 2
    ) -> Data {
        let sectorSize = 512
        var image = Data(count: totalSectors * sectorSize)
        var entries = Data(count: entryCount * 128)
        writeGPTUUID("7C3457EF-0000-11AA-AA11-00306543ECAC", to: &entries, offset: 0)
        writeUInt64(40, to: &entries, offset: 32)
        writeUInt64(UInt64(mainLast), to: &entries, offset: 40)
        writeGPTUUID("52637672-7900-11AA-AA11-00306543ECAC", to: &entries, offset: 128)
        writeUInt64(UInt64(recoveryFirst), to: &entries, offset: 160)
        writeUInt64(UInt64(recoveryLast), to: &entries, offset: 168)
        image.replaceSubrange((2 * sectorSize)..<(2 * sectorSize + entries.count), with: entries)

        var header = Data(count: sectorSize)
        header.replaceSubrange(0..<8, with: Data("EFI PART".utf8))
        writeUInt32(0x0001_0000, to: &header, offset: 8)
        writeUInt32(92, to: &header, offset: 12)
        writeUInt64(1, to: &header, offset: 24)
        writeUInt64(UInt64(totalSectors - 1), to: &header, offset: 32)
        let entrySectors = (entryCount * 128 + sectorSize - 1) / sectorSize
        writeUInt64(UInt64(max(34, 2 + entrySectors)), to: &header, offset: 40)
        writeUInt64(UInt64(totalSectors - 41), to: &header, offset: 48)
        writeUInt64(2, to: &header, offset: 72)
        writeUInt32(UInt32(entryCount), to: &header, offset: 80)
        writeUInt32(128, to: &header, offset: 84)
        writeUInt32(crc32(of: entries), to: &header, offset: 88)
        writeUInt32(crc32(of: header.prefix(92)), to: &header, offset: 16)
        image.replaceSubrange(sectorSize..<(2 * sectorSize), with: header)
        return image
    }

    private func crc32(of data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(bytes.count)))
        }
    }

    private func writeGPTUUID(_ string: String, to data: inout Data, offset: Int) {
        let uuid = UUID(uuidString: string)!.uuid
        let bytes = [
            uuid.3, uuid.2, uuid.1, uuid.0,
            uuid.5, uuid.4,
            uuid.7, uuid.6,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15,
        ]
        data.replaceSubrange(offset..<(offset + 16), with: bytes)
    }

    private func writeUInt64(_ value: UInt64, to data: inout Data, offset: Int) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 8), with: $0) }
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, offset: Int) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }
}
