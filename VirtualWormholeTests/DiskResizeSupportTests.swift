//
//  DiskResizeSupportTests.swift
//  VirtualWormholeTests
//
//  Created by VirtualBuddy on 26/05/26.
//

import XCTest
@testable import VirtualCore

final class DiskResizeSupportTests: XCTestCase {

    @MainActor
    func testDiskResizeCheckDoesNothingWithoutPendingMetadataFlag() async throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        var vm = try VBVirtualMachine(bundleURL: bundleURL, isNewInstall: true)
        let image = VBManagedDiskImage(id: "boot-disk", filename: "Disk", size: 2 * .storageGigabyte, format: .raw)
        vm.configuration.hardware.storageDevices = [
            VBStorageDevice(
                id: "boot",
                isBootVolume: true,
                isReadOnly: false,
                isUSBMassStorageDevice: false,
                backing: .managedImage(image)
            )
        ]

        var messages = [String]()
        try await vm.checkAndResizeDiskImages { message in
            messages.append(message)
        }

        XCTAssertTrue(messages.isEmpty)
    }

    func testMetadataTracksPendingDiskResizeIDs() {
        let image = VBManagedDiskImage(id: "boot-disk", filename: "Disk", size: .storageGigabyte, format: .raw)
        var metadata = VBVirtualMachine.Metadata()

        XCTAssertFalse(metadata.hasPendingDiskImageResizes)

        metadata.markDiskImageResizePending(for: image)

        XCTAssertTrue(metadata.hasPendingDiskImageResizes)
        XCTAssertEqual(metadata.pendingDiskImageResizeIDs, ["boot-disk"])

        metadata.clearPendingDiskImageResize(for: image)

        XCTAssertFalse(metadata.hasPendingDiskImageResizes)
    }

    func testSelectableResizeLimitUsesOnlyAvailableHostSpace() {
        let currentSize = 64 * UInt64.storageGigabyte
        let maximumSize = 512 * UInt64.storageGigabyte
        let availableSpace = 24 * UInt64.storageGigabyte

        let limit = VBManagedDiskImage.maximumSelectableSize(
            configuredMaximum: maximumSize,
            minimumSize: currentSize,
            existingImageSize: currentSize,
            availableSpace: availableSpace,
            volumeCapacity: 256 * .storageGigabyte
        )

        XCTAssertEqual(limit, 88 * .storageGigabyte)
    }

    func testSelectableResizeLimitNeverFallsBelowMinimumSize() {
        let currentSize = 128 * UInt64.storageGigabyte

        let limit = VBManagedDiskImage.maximumSelectableSize(
            configuredMaximum: 512 * .storageGigabyte,
            minimumSize: currentSize,
            existingImageSize: currentSize,
            availableSpace: 4 * .storageGigabyte,
            volumeCapacity: 96 * .storageGigabyte
        )

        XCTAssertEqual(limit, currentSize)
    }

    func testResizeConfirmationIsOnlyRequiredForExplicitExpansion() {
        XCTAssertTrue(
            VBManagedDiskImage.requiresResizeConfirmation(
                isExistingDiskImage: true,
                canResize: true,
                originalSize: 64 * .storageGigabyte,
                proposedSize: 128 * .storageGigabyte
            )
        )

        XCTAssertFalse(
            VBManagedDiskImage.requiresResizeConfirmation(
                isExistingDiskImage: true,
                canResize: true,
                originalSize: 64 * .storageGigabyte,
                proposedSize: 64 * .storageGigabyte
            )
        )

        XCTAssertFalse(
            VBManagedDiskImage.requiresResizeConfirmation(
                isExistingDiskImage: false,
                canResize: true,
                originalSize: 64 * .storageGigabyte,
                proposedSize: 128 * .storageGigabyte
            )
        )
    }

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

    func testRawDiskAtConfiguredSizeStillReconcilesPartitions() {
        let size = UInt64.storageGigabyte

        XCTAssertTrue(VBDiskResizer.shouldReconcilePartitions(configuredSize: size, actualSize: size, format: .raw))
    }

    func testASIFDiskAtConfiguredSizeReconcilesPartitionsOnSupportedSystems() {
        let size = UInt64.storageGigabyte

        if #available(macOS 26, *) {
            XCTAssertTrue(VBDiskResizer.shouldReconcilePartitions(configuredSize: size, actualSize: size, format: .asif))
        } else {
            XCTAssertFalse(VBDiskResizer.shouldReconcilePartitions(configuredSize: size, actualSize: size, format: .asif))
        }
    }

    func testGrowingDiskDoesNotRunSeparatePartitionReconciliationFirst() {
        XCTAssertFalse(
            VBDiskResizer.shouldReconcilePartitions(
                configuredSize: 2 * .storageGigabyte,
                actualSize: .storageGigabyte,
                format: .raw
            )
        )
    }
}
