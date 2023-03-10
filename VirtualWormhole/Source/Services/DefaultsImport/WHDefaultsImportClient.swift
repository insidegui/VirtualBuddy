//
//  WHDefaultsImportClient.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 10/03/23.
//

import Foundation
import OSLog

public final class WHDefaultsImportClient: WormholeServiceClient {

    private lazy var logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: String(describing: Self.self))

    public typealias ServiceType = WHDefaultsImportService

    let service: WHDefaultsImportService

    public init(with service: WHDefaultsImportService) {
        self.service = service
    }

    public func importDomain(with id: DefaultsDomainDescriptor.ID) async throws {
        logger.debug("Requesting export for \(id, privacy: .public)")

        let response = Task {
            let stream = service.onDomainResponseReceived.filter({ $0.domainID == id }).values

            for await response in stream {
                switch response {
                case .failure(_, let message):
                    logger.error("Export request for \(id, privacy: .public) resolved with error: \(message, privacy: .public)")

                    throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: message])
                case .success(let id, let data):
                    logger.debug("Export request for \(id, privacy: .public) resolved successfully")

                    try await performImport(for: id, with: data)
                default:
                    continue
                }
                break
            }
        }

        await service.sendExportRequest(for: id)

        logger.debug("Export request for \(id, privacy: .public) sent, waiting for response")

        try await response.value
    }

    private func performImport(for domainID: String, with data: Data) async throws {
        let domain = try service.fetchDescriptor(for: domainID)

        let tempURL = service.temporaryURL(for: domainID)

        try data.write(to: tempURL)

        try await domain.importDefaults(from: tempURL)

        try? FileManager.default.removeItem(at: tempURL)
    }

}
