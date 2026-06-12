import Foundation

final class TestDeviceRestoreBackend: DeviceRestoreBackend, @unchecked Sendable {
    let stateDictionaries: [CFDictionary]
    let minTransitionIntervalMS: Int
    let maxTransitionIntervalMS: Int

    init(stateDictionaries: [CFDictionary] = DeviceRestoreState.testDictionaries, minTransitionIntervalMS: Int = 5, maxTransitionIntervalMS: Int = 30) {
        self.stateDictionaries = stateDictionaries
        self.minTransitionIntervalMS = minTransitionIntervalMS
        self.maxTransitionIntervalMS = maxTransitionIntervalMS
    }

    func restore(deviceECID: ECID, options: [String : AnyHashable], loggers: DeviceRestoreLoggers, progress: @escaping DeviceRestoreProgressClosure) throws {
        Task {
            for dictionary in stateDictionaries {
                progress(dictionary)

                do {
                    try await Task.sleep(for: .milliseconds(Int.random(in: minTransitionIntervalMS...maxTransitionIntervalMS)))
                } catch { break }
            }
        }
    }
}

private extension String {
    static let testRestoreBackendLog: String = {
        guard let url = Bundle.virtualInstallation.url(forResource: "RestoreStates-VMA2", withExtension: "txt") else {
            fatalError("Missing RestoreStates-VMA2 file in VirtualInstallation bundle for test")
        }
        return try! String(contentsOf: url, encoding: .utf8)
    }()
}

extension DeviceRestoreState {
    nonisolated(unsafe) static var testDictionaries: [CFDictionary] = {
        let dictionaries = readRestoreStatesFromLog(String.testRestoreBackendLog)
        return dictionaries
    }()

    static let testStates: [DeviceRestoreState] = {
        return try! testDictionaries.map {
            try DeviceRestoreState(info: $0)
        }
    }()

    static let testStatesDistinctOperationsOnly: [DeviceRestoreState] = {
        var statesByOperation: [RestoreOperation: DeviceRestoreState] = [:]

        for state in testStates {
            let operation = state.operation
            if statesByOperation[operation] == nil { statesByOperation[operation] = state }
        }

        return Array(statesByOperation.values).sorted { stateA, stateB in
            guard let idxA = testStates.firstIndex(of: stateA),
                  let idxB = testStates.firstIndex(of: stateB) else {
                return false
            }

            return idxA < idxB
        }
    }()

    static let testStatesError: [DeviceRestoreState] = {
        testStatesDistinctOperationsOnly.prefix(testStatesDistinctOperationsOnly.count - 2) + [.testError]
    }()
}

// MARK: - Test Content

private extension DeviceRestoreState {
    static let test1 = DeviceRestoreState(
        progress: 0.5,
        overallProgress: 0.34,
        operation: 200,
        operationName: AMRLocalizedCopyStringForAMROperation(200) as String,
        status: "Restoring",
        outcome: nil
    )

    static let testError = DeviceRestoreState(
        progress: 1,
        overallProgress: 1,
        operation: 0,
        operationName: AMRLocalizedCopyStringForAMROperation(0) as String,
        status: "Failed",
        outcome: .failure(CodableError(NSError.testRestoreError))
    )
}

private extension NSError {
    static var testRestoreError: NSError {
        NSError(domain: "AMRestoreErrorDomain", code: 3194, userInfo: [
            NSLocalizedDescriptionKey : "Personalization failed",
            NSUnderlyingErrorKey: NSError(domain: "AMRestoreErrorDomain", code: 3194, userInfo: [
                NSLocalizedDescriptionKey: "Declined to authorize this image on this device for this user."
            ])
        ])
    }
}

/**
 Given a log string containing raw logged restore states from MobileDevice, constructs CFDictionary entries matching the restore states.
 Log format is expected to be the debug descriptions of CFDictionary as printed by RestoreBuddy when running, example:
 ```
 PROGRESS: {
     DeviceState = 1;
     Operation = 208;
     OverallProgress = "-1";
     Progress = "-1";
     QueuePosition = 1;
     Status = Restoring;
 }
 PROGRESS: {
     DeviceState = 1;
     Operation = 2;
     OverallProgress = "-1";
     Progress = 0;
     Status = Restoring;
 }
 ```
 */
private func readRestoreStatesFromLog(_ log: String) -> [CFDictionary] {
    let regex = /\s{1,}?(.*)\s?\=\s?(.*);/
    let valueCleanupRegex = /[=;\"]/
    var output = [CFDictionary]()
    let entries = log.components(separatedBy: "}").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    for entry in entries {
        var dict = [String: Any]()

        let matches = entry.matches(of: regex)

        for match in matches {
            let key = match.output.1.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = match.output.2
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacing(valueCleanupRegex, with: { _ in "" })
            switch key {
            case "DeviceState", "Progress", "OverallProgress", "QueuePosition":
                dict[key] = Int(value)
            case "Operation":
                dict[key] = RestoreOperation(value)
            default:
                dict[key] = value
            }

        }

        output.append(dict as CFDictionary)
    }

    return output
}
