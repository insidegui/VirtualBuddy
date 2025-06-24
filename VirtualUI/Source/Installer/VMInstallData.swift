import Foundation
import VirtualCore
import BuddyKit

struct VMInstallData: Hashable, Codable {
    // MARK: Persisted State

    @DecodableDefault.EmptyPlaceholder
    var systemType: VBGuestType = .empty

    var installMethod: InstallMethod { installMethodSelection?.id ?? .empty }

    var installMethodSelection: InstallMethodSelection? = nil

    var backgroundHash: BlurHashToken = .virtualBuddyBackground

    var name = RandomNameGenerator.shared.newName()

    /// URL to the local restore image that will be used to restore the VM.
    /// This will be the custom local file selected by the user, or the URL to the local file
    /// that's been downloaded from either a custom remote URL or a selected restore image option.
    private(set) var localRestoreImageURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        /// Cookie is not stored because it would end up in clear text on the file system when the struct is encoded...
        case systemType, installMethodSelection, backgroundHash, name, localRestoreImageURL
    }

    // MARK: Temporary State

    /// This can be the restore image selected by the user in the UI, or a matching restore image
    /// from the software catalog inferred from a user-provided custom download link or existing local file.
    @MainActor
    private(set) var restoreImage: RestoreImage? = nil {
        didSet {
            /// Ensure background hash is set to whatever restore image group ends up being used,
            /// even if it's matched from user-provided file/url.
            if let group = catalog.groups.first(where: { $0.id == restoreImage?.group }),
               let value = group.darkImage?.thumbnail.blurHash
            {
                backgroundHash = BlurHashToken(value: value)
            } else {
                backgroundHash = systemType == .mac ? .virtualBuddyBackground : .virtualBuddyBackgroundLinux
            }
        }
    }
    var resolvedRestoreImage: ResolvedRestoreImage? = nil {
        didSet {
            restoreImage = resolvedRestoreImage?.image
            localRestoreImageURL = resolvedRestoreImage?.localFileURL
        }
    }

    @DecodableDefault.EmptyString
    var customInstallImageRemoteURL: String = ""

    var cookie: String? = nil
}

// MARK: Convenience

extension VMInstallData {
    var downloadURL: URL? {
        switch installMethodSelection {
        case .remoteManual(let url): url
        case .remoteOptions(let image): image.url
        case .localFile: nil
        case .none: nil
        }
    }

    @MainActor
    var catalog: SoftwareCatalog { SoftwareCatalog.current(for: systemType) }
}

// MARK: Updates / Validation

extension VMInstallData {
    func canContinue(from step: VMInstallationStep) -> Bool {
        switch step {
        case .systemType: true
        case .restoreImageInput: installMethodSelection != nil
        case .restoreImageSelection: restoreImage != nil
        case .name: !name.isEmpty
        case .configuration:
            true // TODO: Implement
        case .download:
            true // TODO: Implement
        case .install:
            true // TODO: Implement
        case .done:
            true // TODO: Implement
        }
    }

    private static let allowedCustomDownloadSchemes: Set<String> = [
        "http",
        "https",
        "ftp"
    ]

    func validateCustomRestoreImageRemoteURL() -> Bool {
        guard !customInstallImageRemoteURL.isEmpty else {
            return false
        }
        guard let url = URL(string: customInstallImageRemoteURL) else {
            return false
        }

        guard let scheme = url.scheme else {
            return false
        }

        guard Self.allowedCustomDownloadSchemes.contains(scheme.lowercased()) else {
            return false
        }

        return true
    }

    mutating func commitSelectedRestoreImage() throws {
        UILog("\(#function) \(String(optional: restoreImage?.url.absoluteString.quoted))")

        installMethodSelection = try .remoteOptions(restoreImage.require("Please select one of the OS versions available."))
    }

    @MainActor
    mutating func commitCustomRestoreImageURL() throws {
        UILog("\(#function) \(customInstallImageRemoteURL.quoted)")

        let customURL = try URL(string: customInstallImageRemoteURL).require("Invalid URL: \(customInstallImageRemoteURL.quoted).")
        installMethodSelection = .remoteManual(customURL)

        /// Attempt to match custom URL with known catalog content.
        restoreImage = catalog.restoreImageMatchingDownloadableCatalogContent(at: customURL)
    }

    @MainActor
    mutating func commitCustomRestoreImageLocalFile(path: String) {
        UILog("\(#function) \(path.quoted)")

        let fileURL = URL(fileURLWithPath: path)
        installMethodSelection = .localFile(fileURL)
        commitLocalRestoreImageURL(fileURL)

        /// Attempt to match custom local file with known catalog content.
        restoreImage = catalog.restoreImageMatchingDownloadableCatalogContent(at: fileURL)
    }

    @MainActor
    mutating func resolveCatalogImageIfNeeded(with model: VBVirtualMachine) throws {
        guard case .remoteOptions(let restoreImage) = installMethodSelection else { return }

        resolvedRestoreImage = try model.resolveCatalogImage(restoreImage)
    }

    mutating func commitLocalRestoreImageURL(_ url: URL) {
        localRestoreImageURL = url
    }

    /// Removes any data associated with the current install method selection if the new selection is a different install method.
    mutating func resetInstallMethodSelectionIfNeeded(selectedMethod: InstallMethod) {
        guard let installMethodSelection else { return }
        guard selectedMethod != installMethodSelection.id else { return }
        self.installMethodSelection = nil
        self.resolvedRestoreImage = nil
    }

    var needsDownload: Bool {
        guard let downloadURL else { return false }

        switch installMethodSelection {
        case .none:
            UILog("[\(#function)] ⚠️ Method is nil!")
            return false
        case .localFile:
            UILog("[\(#function)] Method is \(installMethod), download never needed.")
            return false
        case .remoteManual, .remoteOptions:
            /// `localRestoreImageURL` is set when user selects a remote URL but that file has already been downloaded to the local library.
            /// Check that the file name matches and skip download when that's the case.
            if let localRestoreImageURL, localRestoreImageURL.lastPathComponent == downloadURL.lastPathComponent {
                UILog("[\(#function)] Method is \(installMethod), remote URL is \(downloadURL.absoluteString.quoted), found matching download at \(localRestoreImageURL.path.quoted).")

                return false
            } else {
                UILog("[\(#function)] Method is \(installMethod), remote URL is \(downloadURL.absoluteString.quoted), download is needed.")

                return true
            }
        }
    }
}

extension VBVirtualMachine.Metadata {
    mutating func updateRestoreImageURLs(with data: VMInstallData) {
        /// Always save whatever URL the restore image was downloaded from and the local file URL, regardless of the install method.
        if let downloadURL = data.downloadURL {
            updateInstallImageURL(downloadURL)
        }
        if let localRestoreImageURL = data.localRestoreImageURL {
            updateInstallImageURL(localRestoreImageURL)
        }
    }
}
