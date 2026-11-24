//
//  VBSettingsContainer.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation
import Combine
import ManagedPreferencesKit
import OSLog

public final class VBSettingsContainer: ObservableObject {

    private lazy var logger = Logger(for: Self.self)

    public static let current = VBSettingsContainer()

    @Published public var settings = VBSettings()

    public let defaults: UserDefaults

    public init(with defaults: UserDefaults = .standard) {
        self.defaults = defaults

        read()
        bind()
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private lazy var developerFeaturesPolicy = DefaultsKeyObserver(
        defaults: defaults,
        key: ManagedPreference<VirtualBuddyManagedPreferences, Bool>.disableDeveloperFeatures.key
    )

    /// Whether developer features can be used: the user's setting, unless a configuration profile disables them.
    /// Publishes the current value on subscription, then each change. Changes to the profile are published
    /// on the thread that observed them.
    public var developerFeaturesAvailability: AnyPublisher<Bool, Never> {
        let preferences = VirtualBuddyManagedPreferences.schema.reader(store: UserDefaultsManagedPreferenceStore(defaults))

        return $settings
            .combineLatest(developerFeaturesPolicy.changes.prepend(()))
            .map { settings, _ in (try? settings.requireDeveloperFeatures(preferences: preferences)) != nil }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

}

/// Reports changes to one defaults key, including those made by a configuration profile or another process.
private final class DefaultsKeyObserver: NSObject {
    let changes = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key

        super.init()

        defaults.addObserver(self, forKeyPath: key, context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: key)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        changes.send()
    }
}

// MARK: - Internal Extensions

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
