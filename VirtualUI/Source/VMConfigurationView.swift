//
//  VMConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 17/07/22.
//

import SwiftUI
import VirtualCore

public struct VMConfigurationView: View {
    @EnvironmentObject var controller: VMController

    public init() { }

    public var body: some View {
        Text("Hello, World!")
    }
}

#if DEBUG
struct VMConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMConfigurationView()
            .environmentObject(VMController(with: .preview))
            .padding()
    }
}

#endif
