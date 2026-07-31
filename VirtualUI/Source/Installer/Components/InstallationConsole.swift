//
//  InstallationConsole.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct InstallationConsole: View {

    var predicate: LogStreamer.Predicate
    var startTime: Date

    var body: some View {
        LogConsole(predicate: predicate, startTime: startTime)
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
    }

}

#if DEBUG
#Preview {
    InstallationConsole(predicate: .process("Xcode"), startTime: .now)
        .padding()
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .bottom)
}
#endif
