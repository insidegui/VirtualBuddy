//
//  ContentView.swift
//  VirtualBuddyGuest
//
//  Created by Guilherme Rambo on 02/06/22.
//

import SwiftUI
import VirtualWormhole

extension WormholeManager {
    static let shared = WormholeManager(for: .guest)
}

struct ContentView: View {
    @State var activated = false
    
    var body: some View {
        Text("Guest Service Running")
            .padding()
            .onAppear {
                _ = WormholeManager.shared
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
