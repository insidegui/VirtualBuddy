//
//  InstallationConsole.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore

struct InstallationConsole: View {

    @Binding var isExpanded: Bool

    var overridePredicate: LogStreamer.Predicate? = nil

    private var predicate: LogStreamer.Predicate {
        overridePredicate ?? .process("com.apple.Virtualization.Installation")
    }

    var body: some View {
        ZStack {
            if isExpanded {
                LogConsole(predicate: predicate)
                    .frame(minWidth: 200, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
            } else {
                Button {
                    withAnimation(.spring()) {
                        isExpanded = true
                    }
                } label: {
                    Text("View Installation Logs")
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
                .buttonStyle(.link)
            }
        }
        .controlGroup(level: .secondary)
    }

}

#if DEBUG
struct InstallationConsole_Previews: PreviewProvider {
    static var previews: some View {
        _Template(expanded: true)
            .previewDisplayName("Expanded")

        _Template(expanded: false)
            .previewDisplayName("Collapsed")
    }

    struct _Template: View {
        @State var isExpanded = false
        init(expanded: Bool) {
            self._isExpanded = .init(wrappedValue: expanded)
        }
        var body: some View {
            InstallationConsole(isExpanded: $isExpanded, overridePredicate: .process("Xcode"))
                .padding()
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
#endif
