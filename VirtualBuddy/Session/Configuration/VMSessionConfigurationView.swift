//
//  VMSessionConfigurationView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import SwiftUI
import VirtualCore

struct VMSessionConfigurationView: View {
    @EnvironmentObject var controller: VMController
    
    var body: some View {
        Form {
            Toggle("Boot in recovery mode", isOn: $controller.options.bootInRecoveryMode)
            Toggle("Capture system keyboard shortcuts", isOn: $controller.options.captureSystemKeys)
        }
        .padding()
        .groupBackground()
    }
}

struct GroupBackgroundModifier: ViewModifier {
    
    let material: Material
    
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).foregroundStyle(material))
    }
    
}

extension View {
    func groupBackground(material: Material = .ultraThin) -> some View {
        modifier(GroupBackgroundModifier(material: material))
    }
}

struct VMSessionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        VMSessionConfigurationView()
            .environmentObject(VMController(with: .preview))
            .padding()
    }
}
