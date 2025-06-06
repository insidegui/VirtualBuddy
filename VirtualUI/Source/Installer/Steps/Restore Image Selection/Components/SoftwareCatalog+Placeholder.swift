import SwiftUI
import VirtualCore

extension String {
    static let placeholderID = "__PLACEHOLDER__"
}

extension URL {
    static let catalogPlaceholder = URL(string: "https://example.com")!
    static let catalogGroupPlaceholderImage = Bundle.virtualUI.url(forResource: "CatalogGroupPlaceholder", withExtension: "heic") ?? URL(filePath: "/dev/null")
}

extension CatalogGraphic {
    static let placeholder = CatalogGraphic(
        id: .placeholderID,
        url: .catalogGroupPlaceholderImage,
        thumbnail: CatalogGraphic.Thumbnail(
            url: .catalogGroupPlaceholderImage,
            width: 340,
            height: 720,
            blurHash: "U0Eo[I?bfQ?b?bj[fQj[fQfQfQfQ?bj[fQj["
        )
    )
}

extension CatalogGroup {
    static let placeholder = CatalogGroup(
        id: .placeholderID,
        name: "macOS Placeholder",
        majorVersion: "15.0",
        image: .placeholder,
        darkImage: .placeholder
    )
}

extension ResolvedCatalogGroup {
    static let placeholder = ResolvedCatalogGroup(
        group: .placeholder,
        restoreImages: []
    )
}

extension RestoreImage {
    static let placeholder = RestoreImage(
        id: .placeholderID,
        group: .placeholderID,
        channel: .placeholderID,
        requirements: .placeholderID,
        name: "macOS 15.3 Developer Beta",
        build: "ABC123F",
        version: "15.3",
        mobileDeviceMinVersion: "1.0",
        url: .catalogPlaceholder,
        downloadSize: 1024 * 1024 * 1024 * 8
    )
}

extension CatalogChannel {
    static let placeholder = CatalogChannel(id: .placeholderID, name: "Placeholder", note: "Placeholder", icon: "checkmark.seal")
}

extension RequirementSet {
    static let placeholder = RequirementSet(id: .placeholderID, minCPUCount: 0, minMemorySizeMB: 0, minVersionHost: "1.0")
}

extension ResolvedRequirementSet {
    static let placeholder = ResolvedRequirementSet(requirements: .placeholder, status: .supported)
}

extension SoftwareCatalog {
    static let placeholder = SoftwareCatalog(apiVersion: 1, minAppVersion: "1.0", channels: [.placeholder], groups: [.placeholder], restoreImages: [.placeholder], features: [], requirementSets: [.placeholder])
}

extension ResolvedRestoreImage {
    static let placeholder = ResolvedRestoreImage(image: .placeholder, channel: .placeholder, features: [], requirements: .placeholder, status: .supported)
}
