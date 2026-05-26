//
//  DiskResizeSupportTests.swift
//  VirtualWormholeTests
//
//  Created by VirtualBuddy on 26/05/26.
//

import XCTest
@testable import VirtualCore

final class DiskResizeSupportTests: XCTestCase {

    func testASIFResizeSupportMatchesPlatformSupport() {
        let image = VBManagedDiskImage(filename: "Disk", size: .storageGigabyte, format: .asif)

        if #available(macOS 26, *) {
            XCTAssertTrue(VBDiskResizer.canResizeFormat(.asif))
            XCTAssertTrue(image.canBeResized)
        } else {
            XCTAssertFalse(VBDiskResizer.canResizeFormat(.asif))
            XCTAssertFalse(image.canBeResized)
        }
    }

    func testDMGRemainsUnsupportedForResize() {
        let image = VBManagedDiskImage(filename: "Disk", size: .storageGigabyte, format: .dmg)

        XCTAssertFalse(VBDiskResizer.canResizeFormat(.dmg))
        XCTAssertFalse(image.canBeResized)
    }

    func testDiskutilImageInfoParserReadsASIFTotalBytes() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Image Format</key>
            <string>ASIF</string>
            <key>Size Info</key>
            <dict>
                <key>Total Bytes</key>
                <integer>2000003072</integer>
            </dict>
        </dict>
        </plist>
        """

        let size = try VBDiskResizer.imageSize(fromDiskutilImageInfoPlist: Data(plist.utf8))

        XCTAssertEqual(size, 2_000_003_072)
    }

    func testASIFFileVaultCheckUsesDiskutilImageAttachOnSupportedSystems() {
        let url = URL(fileURLWithPath: "/tmp/Disk.asif")

        if #available(macOS 26, *) {
            let command = VBDiskResizer.fileVaultAttachCommand(for: .asif, at: url)
            XCTAssertEqual(command?.executablePath, "/usr/sbin/diskutil")
            XCTAssertEqual(command?.arguments, ["image", "attach", "--nomount", url.path])

            let detachCommand = VBDiskResizer.fileVaultDetachCommand(for: .asif, deviceNode: "/dev/disk8")
            XCTAssertEqual(detachCommand?.executablePath, "/usr/sbin/diskutil")
            XCTAssertEqual(detachCommand?.arguments, ["eject", "/dev/disk8"])
        } else {
            XCTAssertNil(VBDiskResizer.fileVaultAttachCommand(for: .asif, at: url))
            XCTAssertNil(VBDiskResizer.fileVaultDetachCommand(for: .asif, deviceNode: "/dev/disk8"))
        }
    }

    func testRawFileVaultCheckKeepsHdiutilAttachCommand() {
        let url = URL(fileURLWithPath: "/tmp/Disk.img")

        let command = VBDiskResizer.fileVaultAttachCommand(for: .raw, at: url)
        XCTAssertEqual(command?.executablePath, "/usr/bin/hdiutil")
        XCTAssertEqual(command?.arguments, ["attach", "-imagekey", "diskimage-class=CRawDiskImage", "-nomount", url.path])

        let detachCommand = VBDiskResizer.fileVaultDetachCommand(for: .raw, deviceNode: "/dev/disk4")
        XCTAssertEqual(detachCommand?.executablePath, "/usr/bin/hdiutil")
        XCTAssertEqual(detachCommand?.arguments, ["detach", "/dev/disk4"])
    }

    func testAttachOutputParserPrefersBackingDiskOverSynthesizedAPFSDevices() {
        let output = """
        /dev/disk10         \tEF57347C-0000-11AA-AA11-0030654\t
        /dev/disk10s1       \t41504653-0000-11AA-AA11-0030654\t
        /dev/disk10s2       \t41504653-0000-11AA-AA11-0030654\t
        /dev/disk8          \tGUID_partition_scheme          \t
        /dev/disk8s1        \tApple_APFS_ISC                 \t
        /dev/disk8s2        \tApple_APFS                     \t
        /dev/disk8s3        \tApple_APFS_Recovery            \t
        """

        XCTAssertEqual(VBDiskResizer.deviceNode(fromDiskImageAttachOutput: output), "/dev/disk8")
    }
}
