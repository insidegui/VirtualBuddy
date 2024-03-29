import SwiftUI
import VirtualCore

struct SavedStatePicker: View {
    @EnvironmentObject private var controller: VMSavedStatesController

    @Binding var selection: VBSavedStatePackage?

    var body: some View {
        Picker("State", selection: $selection) {
            if controller.states.isEmpty {
                Text("No Saved States")
                    .tag(Optional<VBSavedStatePackage>.none)
            } else {
                Text("Don’t Restore")
                    .tag(Optional<VBSavedStatePackage>.none)

                Divider()
            }

            ForEach(controller.states) { state in
                Text(state.url.deletingPathExtension().lastPathComponent)
                    .tag(Optional<VBSavedStatePackage>.some(state))
            }
        }
        .disabled(controller.states.isEmpty)
    }
}

#if DEBUG
private struct _Preview: View {
    @StateObject private var controller = VMSavedStatesController.preview
    @State private var selectedState: VBSavedStatePackage?

    var body: some View {
        Form {
            SavedStatePicker(selection: $selectedState)
                .environmentObject(controller)
        }
        .formStyle(.grouped)
    }
}

#Preview("SavedStatePicker") {
    _Preview()
}
#endif
