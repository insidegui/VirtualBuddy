import SwiftUI
import VirtualCore
import BuddyKit

struct InstallProgressDisplayView: View {
    @EnvironmentObject private var viewModel: VMInstallationViewModel
    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VirtualDisplayView {
            VStack {
                switch viewModel.step {
                case .download:
                    RestoreImageDownloadView()
                case .install:
                    InstallProgressStepView()
                case .done:
                    InstallProgressDoneView()
                default:
                    EmptyView()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview(step: .done)
}
#endif
