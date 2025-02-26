import SwiftUI
import VirtualCore

struct SavedStatePicker: View {
    @EnvironmentObject private var controller: VMSavedStatesController

    @Binding var selectedStateURL: URL?

    var body: some View {
        Picker("State", selection: $selectedStateURL) {
            if controller.states.isEmpty {
                Text("No Saved States")
                    .tag(Optional<URL>.none)
            } else {
                Text("Don’t Restore")
                    .tag(Optional<URL>.none)

                Divider()
            }

            ForEach(controller.states) { state in
                Text(state.url.deletingPathExtension().lastPathComponent)
                    .tag(Optional<URL>.some(state.url))
            }
        }
        .disabled(controller.states.isEmpty)
    }
}

#if DEBUG
private struct _Preview: View {
    @StateObject private var controller = VMSavedStatesController.preview
    @State private var selectedStateURL: URL?

    var body: some View {
        Form {
            SavedStatePicker(selectedStateURL: $selectedStateURL)
                .environmentObject(controller)
        }
        .formStyle(.grouped)
    }
}

#Preview("SavedStatePicker") {
    _Preview()
}
#endif
