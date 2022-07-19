//
//  DiskImageGenerator.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Foundation

enum DiskImageFormat: Int {
    case raw
    case dmg
}

final class DiskImageGenerator {

    static func generateImage(at url: URL, with sizeInBytes: UInt64, name: String, format: DiskImageFormat = .raw) async throws {
        switch format {
        case .raw:
            try generateRaw(at: url, with: sizeInBytes, name: name)
        case .dmg:
            try await generateDMG(at: url, with: sizeInBytes, name: name)
        }
    }

    private static func generateRaw(at url: URL, with sizeInBytes: UInt64, name: String) throws {
        let diskFd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        if diskFd == -1 {
            throw Failure("Cannot create disk image.")
        }

        var result = ftruncate(diskFd, off_t(sizeInBytes))
        if result != 0 {
            throw Failure("ftruncate() failed.")
        }

        result = close(diskFd)
        if result != 0 {
            throw Failure("Failed to close the disk image.")
        }
    }

    private static func generateDMG(at url: URL, with sizeInBytes: UInt64, name: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-megabytes",
            "\(sizeInBytes / .storageMegabyte)",
            "-fs",
            "APFS",
            "-volname",
            name,
            url.path
        ]
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
            throw Failure("hdiutil failed with exit code \(process.terminationStatus)")
        }
    }

}
