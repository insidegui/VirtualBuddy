//
//  CatalogExtensions.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 02/08/24.
//

import Foundation

@MainActor
public extension SoftwareCatalog {
    /// The most up-to-date software catalog available for Mac releases.
    /// This is updated when the API client fetches a new catalog from the server.
    private(set) static var currentMacCatalog: SoftwareCatalog = {
        do {
            return try VBAPIClient.fetchBuiltInCatalog(for: .mac)
        } catch {
            assertionFailure("Built-in catalog load failed: \(error)")
            return SoftwareCatalog.empty
        }
    }()

    /// The most up-to-date software catalog available for Linux releases.
    /// This is updated when the API client fetches a new catalog from the server.
    private(set) static var currentLinuxCatalog: SoftwareCatalog = {
        do {
            return try VBAPIClient.fetchBuiltInCatalog(for: .linux)
        } catch {
            assertionFailure("Built-in catalog load failed: \(error)")
            return SoftwareCatalog.empty
        }
    }()

    static func current(for guestType: VBGuestType) -> SoftwareCatalog {
        switch guestType {
        case .mac: return .currentMacCatalog
        case .linux: return .currentLinuxCatalog
        }
    }

    static func setCurrent(_ catalog: SoftwareCatalog, for guestType: VBGuestType) {
        switch guestType {
        case .mac:
            self.currentMacCatalog = catalog
        case .linux:
            self.currentLinuxCatalog = catalog
        }
    }
}

public extension CatalogGuestPlatform {
    init(_ guestType: VBGuestType) {
        switch guestType {
        case .mac:
            self = .mac
        case .linux:
            self = .linux
        }
    }
}

public extension CatalogResolutionEnvironment {
    func guestType(_ guestType: VBGuestType) -> Self {
        guest(platform: CatalogGuestPlatform(guestType))
    }
}

public extension VBVirtualMachine {
    @MainActor
    func resolveCatalogImage(_ image: RestoreImage, catalog: SoftwareCatalog? = nil) throws -> ResolvedRestoreImage {
        try configuration.resolveCatalogImage(image, catalog: catalog)
    }
}

public extension VBMacConfiguration {
    @MainActor
    func resolveCatalogImage(_ image: RestoreImage, catalog: SoftwareCatalog? = nil) throws -> ResolvedRestoreImage {
        let effectiveCatalog = catalog ?? SoftwareCatalog.current(for: systemType)
        return try ResolvedRestoreImage(
            environment: .current.guestType(systemType),
            catalog: effectiveCatalog,
            image: image
        )
    }
}
