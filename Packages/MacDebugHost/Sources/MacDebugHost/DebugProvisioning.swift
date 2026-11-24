import CryptoKit
import Foundation
import MacDebugProtocol
import Security

public struct DebugProvisioningRequest: Sendable {
    public let destination: UUID
    public let teamID: String
    public let udid: String
    public let bundleIDs: [String]
    public let automaticSigning: Bool
    public let detail: String?
}

public enum DebugProvisioningAction: Sendable {
    case retry
    case importProfiles([URL])
}

@MainActor
public protocol DebugProvisioningInteraction: AnyObject, Sendable {
    func showProgress(destination: UUID, detail: String, cancel: @escaping @MainActor () -> Void)
    func resolve(_ request: DebugProvisioningRequest) async throws -> DebugProvisioningAction
    func dismiss(destination: UUID)
}

public struct DebugProvisioning: Sendable {
    let cache: URL
    let interaction: any DebugProvisioningInteraction
    var xcodeProfileDirectories: [URL]

    public init(cacheDirectory: URL, interaction: any DebugProvisioningInteraction) {
        self.cache = cacheDirectory
        self.interaction = interaction
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        xcodeProfileDirectories = [library.appendingPathComponent("Developer/Xcode/UserData/Provisioning Profiles"),
                                   library.appendingPathComponent("MobileDevice/Provisioning Profiles")]
    }

    @MainActor
    func prepare(_ build: DebugBuild, session: any RemoteDebugSession, run: UUID, work: URL,
                 cancel: @escaping @MainActor @Sendable () -> Void) async throws -> URL {
        let worker = ProvisioningRun(configuration: self, build: build, work: work, cancel: cancel)
        defer { interaction.dismiss(destination: build.destination) }
        return try await worker.prepare { try await session.provisioningUDID(for: run) }
    }
}

/// Each Run owns its archive and staging directory. The shared profile cache contains
/// immutable, atomically written assets and never contains a signed build or private key.
private actor ProvisioningRun {
    private struct Target {
        let bundle: URL
        let profile: URL
        let signature: DebugCodeSignature
        let original: DevelopmentProfile
        let needsReseal: Bool
        let cache: URL
        var selected: DevelopmentProfile?
    }

    private let configuration: DebugProvisioning
    private let build: DebugBuild
    private let work: URL
    private let product: URL
    private var udid = ""
    private var targets: [Target] = []
    private let cancel: @MainActor @Sendable () -> Void
    private let fm = FileManager.default

    init(configuration: DebugProvisioning, build: DebugBuild, work: URL, cancel: @escaping @MainActor @Sendable () -> Void) {
        self.configuration = configuration
        self.build = build
        self.work = work
        self.cancel = cancel
        product = build.product.resolvingSymlinksInPath().standardizedFileURL
    }

    private func progress(_ text: String) async {
        await configuration.interaction.showProgress(destination: build.destination, detail: text, cancel: cancel)
    }

    func prepare(identify: @Sendable () async throws -> String) async throws -> URL {
        let profiles = try EmbeddedProfiles.find(in: product)
        guard !profiles.isEmpty else { return product }
        guard try DebugCodeSignature(product).entitlements["com.apple.security.get-task-allow"] as? Bool == true else {
            throw MacDebugError("Build a Debug app with com.apple.security.get-task-allow before provisioning it for this Mac.")
        }
        udid = try await identify()
        guard udid.wholeMatch(of: /^[A-Fa-f0-9-]{16,64}$/) != nil else {
            throw MacDebugError("The destination returned an invalid provisioning UDID.")
        }
        for profile in profiles {
            let bundle = profile.deletingLastPathComponent().deletingLastPathComponent()
            let signature = try DebugCodeSignature(bundle)
            guard let team = signature.team, signature.certificate != nil else {
                throw MacDebugError("Build \(signature.identifier) with an Apple Development signing identity.")
            }
            let original = try DevelopmentProfile(profile)
            let bucket = SHA256.hash(data: Data([team, signature.identifier, signature.identity].joined(separator: "\n").utf8))
            let cache = configuration.cache.appendingPathComponent(bucket.map { String(format: "%02x", $0) }.joined())
            targets.append(Target(bundle: bundle, profile: profile, signature: signature, original: original,
                                  needsReseal: try signature.needsProfileReseal(at: profile), cache: cache,
                                  selected: original.authorizes(signature, original: original, udid: udid) ? original : nil))
        }
        if targets.contains(where: { $0.selected == nil }) {
            try await resolveMissingProfiles()
        }
        guard targets.contains(where: { $0.needsReseal || $0.selected?.data != $0.original.data }) else {
            try verify(product)
            return product
        }
        await progress("Signing the app for this Mac…")
        let staged = work.appendingPathComponent("Deployment").appendingPathComponent(product.lastPathComponent)
        try await copyAndSign(to: staged, useSelected: true)
        return staged
    }

    private func resolveMissingProfiles() async throws {
        let stores = configuration.xcodeProfileDirectories
        var searched = Set<URL>()
        for dir in targets.map(\.cache) + stores where searched.insert(dir).inserted {
            try Task.checkCancellation()
            guard targets.contains(where: { $0.selected == nil }) else { return }
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            try select(from: files.filter { ["provisionprofile", "mobileprovision"].contains($0.pathExtension) })
        }
        var didRefresh = Set<String>()
        var detail: String?
        while let missing = targets.first(where: { $0.selected == nil }), let team = missing.signature.team {
            try Task.checkCancellation()
            if build.automaticSigning && didRefresh.insert(team).inserted {
                await progress("Refreshing development profiles with Xcode…")
                do {
                    try await refresh(team: team)
                    detail = nil
                } catch {
                    try Task.checkCancellation()
                    detail = error.localizedDescription
                }
                continue
            }
            let ids = targets.filter { $0.selected == nil && $0.signature.team == team }.map(\.signature.identifier)
            let request = DebugProvisioningRequest(destination: build.destination, teamID: team, udid: udid,
                                                   bundleIDs: ids, automaticSigning: build.automaticSigning, detail: detail)
            switch try await configuration.interaction.resolve(request) {
            case .retry:
                didRefresh.remove(team)
                for store in stores {
                    try select(from: (try? fm.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)) ?? [])
                }
                detail = nil
            case .importProfiles(let files):
                let before = targets.filter { $0.selected == nil }.count
                try select(from: files)
                detail = targets.filter { $0.selected == nil }.count == before
                    ? "The selected profiles must cover this Mac, the app’s identifier, signing certificate and entitlements." : nil
            }
        }
    }

    private func select(from files: [URL]) throws {
        for file in files {
            try Task.checkCancellation()
            guard targets.contains(where: { $0.selected == nil }) else { return }
            guard let candidate = try? DevelopmentProfile(file) else { continue }
            for i in targets.indices where targets[i].selected == nil {
                let target = targets[i]
                guard candidate.authorizes(target.signature, original: target.original, udid: udid) else { continue }
                try DebugTools.directory(target.cache)
                let digest = SHA256.hash(data: candidate.data).map { String(format: "%02x", $0) }.joined()
                let cached = target.cache.appendingPathComponent(digest + ".provisionprofile")
                if cached != file { try candidate.data.write(to: cached, options: .atomic) }
                targets[i].selected = candidate
            }
        }
    }

    /// Export the exact Run product in an isolated archive. Rebuilding the user's scheme
    /// from its own pre-action would risk recursion and a locked build database.
    private func refresh(team: String) async throws {
        let scratch = work.appendingPathComponent(UUID().uuidString)
        try DebugTools.directory(scratch)
        defer { try? fm.removeItem(at: scratch) }
        let archive = scratch.appendingPathComponent("Run.xcarchive")
        let relative = "Applications/" + product.lastPathComponent
        let app = archive.appendingPathComponent("Products/" + relative)
        try await copyAndSign(to: app, useSelected: false)
        guard let info = Bundle(url: product)?.infoDictionary, let id = info["CFBundleIdentifier"] as? String else {
            throw MacDebugError("Could not read the Run product’s bundle identifier.")
        }
        var properties: [String: Any] = ["ApplicationPath": relative, "CFBundleIdentifier": id, "Team": team]
        for key in ["CFBundleVersion", "CFBundleShortVersionString"] { properties[key] = info[key] }
        let name = product.deletingPathExtension().lastPathComponent
        try writePlist(["ArchiveVersion": 2, "CreationDate": Date(), "Name": name, "SchemeName": name,
                        "ApplicationProperties": properties], to: archive.appendingPathComponent("Info.plist"))
        let options = scratch.appendingPathComponent("ExportOptions.plist")
        try writePlist(["method": "debugging", "signingStyle": "automatic", "teamID": team, "stripSwiftSymbols": false], to: options)
        let output = scratch.appendingPathComponent("Export")
        let logURL = scratch.appendingPathComponent("export.log")
        try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        do {
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/xcodebuild"), [
                "-exportArchive", "-archivePath", archive.path, "-exportPath", output.path,
                "-exportOptionsPlist", options.path, "-allowProvisioningUpdates"
            ], log: log, environment: Self.systemXcodeEnvironment)
        } catch {
            try Task.checkCancellation()
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let reason = output.components(separatedBy: .newlines).first { $0.localizedCaseInsensitiveContains("error:") }
            throw MacDebugError(reason ?? "Xcode could not export development profiles. Check the signing account in Xcode Settings, and that xcode-select points to Xcode.")
        }
        try select(from: EmbeddedProfiles.find(in: output))
    }

    /// xcodebuild runs every tool in its developer directory, and /usr/bin/xcodebuild runs
    /// whichever directory DEVELOPER_DIR names without checking who signed it. The Run action's
    /// directory comes from an unprivileged process, so profiles are refreshed with the Xcode
    /// an administrator selected with xcode-select, in an environment that cannot redirect it.
    private static let systemXcodeEnvironment: [String: String] = {
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for name in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "__CF_USER_TEXT_ENCODING"] {
            environment[name] = inherited[name]
        }
        return environment
    }()

    private func writePlist(_ value: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

    private func copyAndSign(to copy: URL, useSelected: Bool) async throws {
        try DebugTools.directory(copy.deletingLastPathComponent())
        try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/ditto"), [product.path, copy.path])
        var resign: [URL: DebugCodeSignature] = [:]
        var replacements: [(URL, Data)] = []
        func staged(_ original: URL) throws -> URL {
            let path = original.standardizedFileURL.path
            if path == product.path { return copy }
            let prefix = product.path + "/"
            guard path.hasPrefix(prefix) else { throw MacDebugError("A signed component is outside the Run product.") }
            return copy.appendingPathComponent(String(path.dropFirst(prefix.count)))
        }
        for target in targets {
            let replacement = useSelected ? target.selected : nil
            let changed = replacement.map { $0.data != target.original.data } ?? false
            guard changed || target.needsReseal else { continue }
            guard try Data(contentsOf: staged(target.profile)) == target.original.data,
                  try DebugCodeSignature(staged(target.bundle)).codeHash == target.signature.codeHash else {
                throw MacDebugError("Xcode changed the Run product during provisioning. Run the scheme again.")
            }
            if changed, let replacement { replacements.append((target.profile, replacement.data)) }
            var url = target.bundle
            while url.path == product.path || url.path.hasPrefix(product.path + "/") {
                if resign[url] == nil, url.path == product.path || url.path == target.bundle.path ||
                    fm.fileExists(atPath: url.appendingPathComponent("Contents/_CodeSignature/CodeResources").path) ||
                    (url.pathExtension == "framework" && Bundle(url: url)?.executableURL != nil) {
                    let signature = try DebugCodeSignature(staged(url))
                    let profile = targets.first { $0.bundle.path == url.path }?.profile
                    _ = try signature.needsProfileReseal(at: profile.map(staged))
                    resign[url] = signature
                }
                url.deleteLastPathComponent()
            }
        }
        for (profile, data) in replacements { try data.write(to: staged(profile), options: .atomic) }
        for (bundle, signature) in resign.sorted(by: { $0.key.pathComponents.count > $1.key.pathComponents.count }) {
            try await DebugTools.run(URL(fileURLWithPath: "/usr/bin/codesign"), [
                "--force", "--sign", signature.identity, "--timestamp=none",
                "--preserve-metadata=identifier,entitlements,requirements,flags,runtime,launch-constraints,library-constraints",
                staged(bundle).path
            ])
            let signed = try DebugCodeSignature(staged(bundle))
            guard signed.identity == signature.identity, signed.identifier == signature.identifier,
                  (signed.entitlements as NSDictionary).isEqual(to: signature.entitlements) else {
                throw MacDebugError("Signing changed the identity or entitlements of \(signature.identifier).")
            }
        }
        try verify(copy)
    }

    private func verify(_ url: URL) throws {
        let signature = try DebugCodeSignature(url)
        guard SecStaticCodeCheckValidity(signature.code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw MacDebugError("Code-signature verification failed for \(url.lastPathComponent). Rebuild the app in Xcode.")
        }
    }
}
