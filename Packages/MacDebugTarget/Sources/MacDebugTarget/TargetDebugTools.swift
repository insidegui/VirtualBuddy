import Foundation
import MacDebugProtocol
import Security

extension DebugSystemImages {
    static func collect() throws -> (Self, [String: URL]) {
        let fm = FileManager.default
        for directory in ["/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld", "/System/Library/dyld"] {
            let folder = URL(fileURLWithPath: directory)
            guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for arch in ["arm64e", "arm64"] {
                let primary = "dyld_shared_cache_" + arch
                guard let cache = contents.first(where: { $0.lastPathComponent == primary }) else { continue }
                let handle = try FileHandle(forReadingFrom: cache)
                defer { try? handle.close() }
                guard let header = try handle.read(upToCount: 104), header.count == 104,
                      header.starts(with: Data("dyld_v1".utf8)) else { throw MacDebugError("Unknown dyld cache format.") }
                let uuid = header.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(fromByteOffset: 88, as: uuid_t.self)) }
                var urls = ["dyld": URL(fileURLWithPath: "/usr/lib/dyld")]
                for file in contents where file.lastPathComponent == primary || file.lastPathComponent.hasPrefix(primary + ".") {
                    urls[file.lastPathComponent] = file
                }
                let system = try NSDictionary(contentsOf: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"), error: ())
                guard let build = system["ProductBuildVersion"] as? String, let version = system["ProductVersion"] as? String else {
                    throw MacDebugError("Could not identify this version of macOS.")
                }
                let files = try urls.sorted { $0.key < $1.key }.map { name, url in
                    File(name: name, bytes: Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0))
                }
                let images = Self(version: version, build: build, architecture: arch, uuid: uuid, files: files)
                try images.validate()
                return (images, urls)
            }
        }
        throw MacDebugError("Could not locate the target’s dyld shared cache.")
    }
}

enum TargetDebugTools {
    static func debugger() throws -> URL {
        let candidates = ["/Library/Developer/CommandLineTools/Library/PrivateFrameworks/LLDB.framework/Resources/debugserver"] +
            ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []).sorted().filter { $0.hasSuffix(".app") && $0.hasPrefix("Xcode") }.map {
                "/Applications/" + $0 + "/Contents/SharedFrameworks/LLDB.framework/Resources/debugserver"
            }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            var code: SecStaticCode?
            var requirement: SecRequirement?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
                  SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { continue }
            return url
        }
        throw MacDebugError("Install Apple’s Command Line Tools or Xcode on the target Mac to provide debugserver.")
    }

    static func install(_ archive: URL, into staging: URL) async throws -> (URL, URL) {
        let fm = FileManager.default
        let unpack = staging.appendingPathComponent("Unpacked")
        try DebugTools.directory(unpack)
        try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, unpack.path])
        let apps = try fm.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let source = apps.first, let bundle = Bundle(url: source),
              let id = bundle.bundleIdentifier, !id.isEmpty, id.utf8.count < 256,
              id.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil,
              let executable = bundle.executableURL, source.resolvingSymlinksInPath().deletingLastPathComponent().path == unpack.resolvingSymlinksInPath().path,
              executable.resolvingSymlinksInPath().path.hasPrefix(source.resolvingSymlinksInPath().path + "/"),
              bundle.executableArchitectures?.contains(NSNumber(value: CPU_TYPE_ARM64)) == true else {
            throw MacDebugError("Build an arm64 macOS app for the target Mac.")
        }
        if let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            guard minimum.compare("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", options: .numeric) != .orderedDescending else {
                throw MacDebugError("This app requires macOS \(minimum) or later.")
            }
        }
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(source as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil) == errSecSuccess else {
            throw MacDebugError("The deployed app has an invalid code signature. Rebuild it in Xcode.")
        }
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let entitlements = (info as NSDictionary?)?[kSecCodeInfoEntitlementsDict] as? [String: Any],
              entitlements["com.apple.security.get-task-allow"] as? Bool == true else {
            throw MacDebugError("Build a signed Debug app with the com.apple.security.get-task-allow entitlement.")
        }
        for profile in try EmbeddedProfiles.find(in: source) {
            do {
                try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/profiles"), ["validate", "-type", "provisioning", "-path", profile.path])
            } catch where !Task.isCancelled {
                let item = profile.deletingLastPathComponent().deletingLastPathComponent()
                throw MacDebugError("macOS rejected the provisioning profile in \(item.lastPathComponent). Check the device registration and the profile’s validity.")
            }
        }
        let folder = staging.deletingLastPathComponent().appendingPathComponent("Apps").appendingPathComponent(id)
        try DebugTools.directory(folder)
        let dest = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            guard renamex_np(source.path, dest.path, UInt32(RENAME_SWAP)) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        } else { try fm.moveItem(at: source, to: dest) }
        return (dest, dest.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable.lastPathComponent))
    }
}
