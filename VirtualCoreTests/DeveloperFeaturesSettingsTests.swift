import Combine
import Foundation
import Testing
@testable import VirtualCore

struct DeveloperFeaturesSettingsTests {
    @Test(arguments: [true, false])
    func detectsXcodeOnceAndPreservesUserChoice(xcodeInstalled: Bool) throws {
        let suiteName = "DeveloperFeaturesSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("saveState", forKey: "closeBehavior")

        var checks = 0
        func readSettings(xcodeInstalled: Bool) throws -> VBSettings {
            try VBSettings(with: defaults) {
                checks += 1
                return xcodeInstalled
            }
        }

        let firstLaunch = try readSettings(xcodeInstalled: xcodeInstalled)
        #expect(firstLaunch.developerFeaturesEnabled == xcodeInstalled)
        #expect(firstLaunch.closeBehavior == .saveState)
        #expect(checks == 1)

        var nextLaunch = try readSettings(xcodeInstalled: !xcodeInstalled)
        #expect(nextLaunch.developerFeaturesEnabled == xcodeInstalled)
        #expect(checks == 1)

        nextLaunch.developerFeaturesEnabled.toggle()
        try nextLaunch.write(to: defaults)
        let afterToggle = try readSettings(xcodeInstalled: xcodeInstalled)
        #expect(afterToggle.developerFeaturesEnabled == !xcodeInstalled)
        #expect(checks == 1)
    }

    @Test func availabilityFollowsTheSettingAndTheRestriction() throws {
        let suiteName = "DeveloperFeaturesSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "developerFeaturesEnabled")

        let container = VBSettingsContainer(with: defaults)
        var values = [Bool]()
        let subscription = container.developerFeaturesAvailability.sink { values.append($0) }
        defer { subscription.cancel() }
        #expect(values == [false])

        container.settings.developerFeaturesEnabled = true
        container.settings.enableTSSCheck.toggle()
        #expect(values == [false, true])

        defaults.set(true, forKey: "DisableDeveloperFeatures")
        #expect(values == [false, true, false])

        defaults.removeObject(forKey: "DisableDeveloperFeatures")
        #expect(values == [false, true, false, true])

        container.settings.developerFeaturesEnabled = false
        #expect(values == [false, true, false, true, false])
    }
}
