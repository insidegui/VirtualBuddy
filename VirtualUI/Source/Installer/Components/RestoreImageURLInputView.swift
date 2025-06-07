import SwiftUI
import VirtualCore

struct RestoreImageURLInputView: View {
    @EnvironmentObject var viewModel: VMInstallationViewModel

    var body: some View {
        VirtualBuddyInstallerInputView {
            TextField("Custom Download Link", text: $viewModel.data.customInstallImageRemoteURL, onCommit: viewModel.next)
        }
        .onChange(of: viewModel.data.customInstallImageRemoteURL) { _ in
            viewModel.validateCustomRemoteURL()
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .restoreImageInput)
}
#endif // DEBUG
