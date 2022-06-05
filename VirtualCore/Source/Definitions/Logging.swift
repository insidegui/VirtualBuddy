//
//  Logging.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 05/06/22.
//

import Foundation
import OSLog

extension Error {
    var log: String { String(describing: self) }
}

extension Logger {
    init<T>(for type: T.Type) {
        self.init(subsystem: VirtualCoreConstants.subsystemName, category: String(describing: type))
    }
}

extension Logger {
    func assert(_ message: String) {
        fault("\(message, privacy: .public)")
        assertionFailure(message)
    }
}
