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

    private(set) var selectedRestoreImage: RestoreImage? = nil
    var resolvedRestoreImage: ResolvedRestoreImage? = nil {
        didSet {
            selectedRestoreImage = resolvedRestoreImage?.image
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

    var needsDownload: Bool {
        UILog("[needsDownload] Method is \(installMethod), downloadURL is \(String(optional: downloadURL))")
        return downloadURL != nil
    }
}

// MARK: Updates / Validation

extension VMInstallData {
    func canContinue(from step: VMInstallationStep) -> Bool {
        switch step {
        case .systemType: true
        case .restoreImageInput: installMethodSelection != nil
        case .restoreImageSelection: selectedRestoreImage != nil
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
        UILog("\(#function) \(String(optional: selectedRestoreImage?.url.absoluteString.quoted))")

        installMethodSelection = try .remoteOptions(selectedRestoreImage.require("Please select one of the OS versions available."))
    }

    mutating func commitCustomRestoreImageURL() throws {
        UILog("\(#function) \(customInstallImageRemoteURL.quoted)")

        installMethodSelection = try .remoteManual(URL(string: customInstallImageRemoteURL).require("Invalid URL: \(customInstallImageRemoteURL.quoted)."))
    }

    mutating func commitCustomRestoreImageLocalFile(path: String) {
        UILog("\(#function) \(path.quoted)")

        let fileURL = URL(fileURLWithPath: path)
        installMethodSelection = .localFile(fileURL)
        commitLocalRestoreImageURL(fileURL)
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
