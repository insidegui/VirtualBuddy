import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("WHRemoteClient is running")
            .task { @MainActor in
                WHXPCService.shared.activate()
            }
    }
}

#Preview {
    ContentView()
}
