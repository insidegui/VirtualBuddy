//
//  InstallationConsole.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct InstallationConsole: View {

    var overridePredicate: LogStreamer.Predicate? = nil

    private var predicate: LogStreamer.Predicate {
        overridePredicate ?? .process("com.apple.Virtualization.Installation")
    }

    var body: some View {
        LogConsole(predicate: predicate)
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 100, maxHeight: 400)
            .controlGroup(level: .secondary)
    }

}

#if DEBUG
#Preview {
    InstallationConsole(overridePredicate: .process("Xcode"))
        .padding()
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .bottom)
}
#endif
