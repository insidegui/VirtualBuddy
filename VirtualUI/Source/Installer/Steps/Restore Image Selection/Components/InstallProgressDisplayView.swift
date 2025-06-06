import SwiftUI
import VirtualCore
import BuddyKit

struct InstallProgressDisplayView: View {
    @EnvironmentObject private var viewModel: VMInstallationViewModel

    var body: some View {
        VirtualDisplayView {
            VStack {
                switch viewModel.step {
                case .download:
                    RestoreImageDownloadView()
                case .install:
                    InstallProgressStepView()
                case .done:
                    VirtualBuddyMonoProgressView(
                        status: Text(viewModel.data.systemType.installFinishedMessage),
                        style: .success
                    )
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
