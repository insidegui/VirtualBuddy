//
//  DefaultsImportController.swift
//  VirtualWormhole
//
//  Created by Guilherme Rambo on 09/03/23.
//

import Foundation
import OSLog
import Combine

public typealias DefaultsDomainCollection = [DefaultsDomainDescriptor.ID: DefaultsDomainDescriptor]

public final class DefaultsImportController: ObservableObject {

    private lazy var logger = Logger(subsystem: VirtualWormholeConstants.subsystemName, category: String(describing: Self.self))

    @Published public private(set) var sortedDomains = [DefaultsDomainDescriptor]()

    @Published public private(set) var descriptors = DefaultsDomainCollection()

    private lazy var cancellables = Set<AnyCancellable>()

    public init() {
        $descriptors
            .map { $0.values.sorted(by: { $0.target.name.localizedStandardCompare($1.target.name) == .orderedAscending }) }
            .assign(to: &$sortedDomains)

        loadDomains()
    }

    private func loadDomains() {
        do {
            guard let url = Bundle.virtualWormhole.url(forResource: "DefaultsDomains", withExtension: "plist") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "DefaultsDomains.plist missing from VirtualWormhole bundle"])
            }

            let data = try Data(contentsOf: url)

            let loadedDescriptors = try PropertyListDecoder().decode(DefaultsDomainCollection.self, from: data)

            self.descriptors = loadedDescriptors
        } catch {
            logger.fault("Failed to load descriptors: \(error, privacy: .public)")
            assertionFailure("Failed to load descriptors: \(error)")
        }
    }

}
