//
//  OnAppearOnce.swift
//  Uploader
//
//  Created by Guilherme Rambo on 22/04/22.
//

import SwiftUI

public extension View {
    
    /// Performs the specified code block the first time the view this modifier is attached to appears.
    /// - Parameter block: The callback to be performed only the first time the view appears.
    func onAppearOnce(perform block: @escaping () -> Void) -> some View {
        modifier(OnAppearOnce(callback: block))
    }
}

private struct OnAppearOnce: ViewModifier {
    
    @State private var performed = false
    let callback: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !performed else { return }
                performed = true
                callback()
            }
    }
    
}
