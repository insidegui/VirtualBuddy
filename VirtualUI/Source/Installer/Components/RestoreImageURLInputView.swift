import SwiftUI
import VirtualCore

struct RestoreImageURLInputView: View {
    @EnvironmentObject var viewModel: VMInstallationViewModel

    @FocusState
    private var focused: Bool

    var body: some View {
        TextField("URL", text: $viewModel.data.customInstallImageRemoteURL, onCommit: viewModel.next)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .focused($focused)
            .onAppear { focused = true }
            .onChange(of: viewModel.data.customInstallImageRemoteURL) { _ in
                viewModel.validateCustomRemoteURL()
            }
    }
}
