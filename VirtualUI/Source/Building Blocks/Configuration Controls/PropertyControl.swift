//
//  PropertyControl.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI

struct PropertyControl<Content: View>: View {
    
    var label: String
    var spacing: CGFloat
    var content: () -> Content
    
    init(_ label: String, spacing: CGFloat = 4, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            PropertyControlLabel(label)
            content().labelsHidden()
        }
    }
    
}

struct PropertyControlLabel: View {
    init(_ title: String) {
        self.title = title
    }
    
    var title: String
    
    var body: some View {
        Text(title)
            .foregroundColor(.white.opacity(0.7))
            .blendMode(.plusLighter)
    }
}
