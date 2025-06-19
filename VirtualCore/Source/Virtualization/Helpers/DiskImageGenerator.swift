//
//  DiskImageGenerator.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Foundation

fileprivate extension VBManagedDiskImage.Format {
    var hdiutilType: String {
        switch self {
        case .raw:
            assertionFailure(".raw not supported with hdiutil")
            return "UDIF"
        case .dmg:
            return "UDIF"
        case .sparse:
            return "SPARSE"
        case .asif:
            return "ASIF"
        }
    }
}

public final class DiskImageGenerator {
    public struct ImageSettings {
        public var url: URL
        public var template: VBManagedDiskImage
        
        public init(for image: VBManagedDiskImage, in vm: VBVirtualMachine) {
            self.url = vm.diskImageURL(for: image)
            self.template = image
        }
    }

    public static func generateImage(with settings: ImageSettings) async throws {
        guard settings.template.format.isSupported else {
            throw "Unsupported disk image format \(settings.template.format.hdiutilType.quoted)."
        }

        switch settings.template.format {
        case .raw:
            try generateRaw(with: settings)
        case .dmg, .sparse:
            try await generateDMG(with: settings)
        case .asif:
            try await generateBlankASIF(with: settings)
        }
    }

    private static func generateRaw(with settings: ImageSettings) throws {
        let diskFd = open(settings.url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if diskFd == -1 {
            throw Failure("Cannot create disk image.")
        }

        var result = ftruncate(diskFd, off_t(settings.template.size))
        if result != 0 {
            throw Failure("ftruncate() failed.")
        }

        result = close(diskFd)
        if result != 0 {
            throw Failure("Failed to close the disk image.")
        }
    }

    private static func generateDMG(with settings: ImageSettings) async throws {
        try await hdiutil(arguments: [
            "create",
            "-layout",
            "GPTSPUD",
            "-type",
            settings.template.format.hdiutilType,
            "-megabytes",
            "\(settings.template.size / .storageMegabyte)",
            "-fs",
            "APFS",
            "-volname",
            settings.template.filename,
            "-nospotlight",
            settings.url.path
        ])
    }

    private static func generateBlankASIF(with settings: ImageSettings) async throws {
        try await diskutil(arguments: [
            "image",
            "create",
            "blank",
            "--fs",
            "none",
            "--format",
            settings.template.format.hdiutilType,
            "--size",
            "\(settings.template.size / .storageGigabyte)G",
            settings.url.path
        ])
    }

    private static func hdiutil(arguments: [String]) async throws {
        try await runCommand("/usr/bin/hdiutil", with: arguments)
    }

    private static func diskutil(arguments: [String]) async throws {
        try await runCommand("/usr/sbin/diskutil", with: arguments)
    }

    private static func runCommand(_ path: String, with arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        #if DEBUG
        print("💻 \(path) arguments: \(process.arguments!.joined(separator: " "))")
        #endif

        let err = Pipe()
        let out = Pipe()
        process.standardError = err
        process.standardOutput = out
        try process.run()

        var error = ""
        for try await line in err.fileHandleForReading.bytes.lines {
            error.append("\(line)\n")
        }

        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return }

        if error.trimmingCharacters(in: .newlines).count > 0 {
            throw Failure(error)
        } else {
            throw Failure("Command \(path) failed with exit code \(process.terminationStatus)")
        }
    }

}
