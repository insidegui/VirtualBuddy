//
//  InstallationWizardTitle.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI

struct InstallationWizardTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    
    var body: some View {
        Text(text)
            .font(.system(.title, design: .rounded).weight(.medium))
            .padding(.vertical, 22)
            .multilineTextAlignment(.center)
    }
}

