//
//  RestoreImageSelectionStep.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore
import Combine

struct RestoreImageSelectionStep: View {
    @StateObject private var controller = RestoreImageSelectionController()
    @EnvironmentObject private var viewModel: VMInstallationViewModel

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.maxContentWidth)
    private var maxContentWidth

    private var browserInsetTop: CGFloat { 100 }

    var body: some View {
        HStack(spacing: 0) {
            CatalogGroupPicker(groups: controller.catalog?.groups, selectedGroup: $controller.selectedGroup)

            RestoreImageBrowser(selection: $viewModel.data.resolvedRestoreImage)
        }
        .redacted(reason: controller.isLoading ? .placeholder : [])
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(controller)
        .task(id: viewModel.data.systemType) {
            controller.loadRestoreImageOptions(for: viewModel.data.systemType)
        }
        .task(id: controller.selectedGroup) {
            if let group = controller.selectedGroup {
                viewModel.data.backgroundHash = BlurHashToken(value: group.darkImage.thumbnail.blurHash)
            } else {
                viewModel.data.backgroundHash = .virtualBuddyBackground
            }
        }
    }

}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
