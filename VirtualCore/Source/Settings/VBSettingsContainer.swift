//
//  VBSettingsContainer.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation
import Combine
import OSLog

public final class VBSettingsContainer: ObservableObject {

    private lazy var logger = Logger(for: Self.self)

    public static let current = VBSettingsContainer()

    @Published public var settings = VBSettings()

    public let defaults: UserDefaults

    init(with defaults: UserDefaults = .standard) {
        self.defaults = defaults

        read()
        bind()
    }

    private lazy var cancellables = Set<AnyCancellable>()

}

private extension VBSettingsContainer {

    func bind() {
        $settings
            .removeDuplicates()
            .throttle(for: 0.2, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] settings in
                self?.write(settings)
            }
            .store(in: &cancellables)
    }

    func read() {
        logger.debug(#function)

        do {
            self.settings = try VBSettings(with: defaults)
        } catch {
            logger.assert("Failed to read settings from defaults: \(error.log)")
        }
    }

    func write(_ newSettings: VBSettings) {
        logger.debug(#function)

        do {
            try newSettings.write(to: defaults)
        } catch {
            logger.assert("Failed to write settings into defaults: \(error.log)")
        }
    }

}
