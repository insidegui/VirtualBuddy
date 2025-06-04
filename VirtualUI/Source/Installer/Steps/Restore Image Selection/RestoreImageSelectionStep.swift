//
//  RestoreImageSelectionStep.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore
import Combine

extension EnvironmentValues {
    @Entry var installationWizardMaxContentWidth: CGFloat = 720
}

struct RestoreImageSelectionStep: View {
    @StateObject private var controller = RestoreImageSelectionController()
    @EnvironmentObject private var viewModel: VMInstallationViewModel

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.installationWizardMaxContentWidth)
    private var maxContentWidth

    private var browserInsetTop: CGFloat { 100 }

    var body: some View {
        HStack(spacing: 0) {
            CatalogGroupPicker(groups: controller.catalog?.groups ?? [], selectedGroup: $controller.selectedGroup)

            if let catalog = controller.catalog, let group = controller.selectedGroup {
                RestoreImageBrowser(catalog: catalog, group: group, selection: $viewModel.data.resolvedRestoreImage)
            }
        }
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
        .background { colorfulBackground }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(controller)
        .padding(-containerPadding)
        .task(id: viewModel.data.systemType) {
            controller.loadRestoreImageOptions(for: viewModel.data.systemType)
        }
    }

    @ViewBuilder
    private var colorfulBackground: some View {
        if let blurHash = controller.selectedGroup?.darkImage.thumbnail.blurHash {
            Image(blurHash: blurHash, size: .init(width: 5, height: 5), punch: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 22, opaque: true)
                .saturation(1.3)
                .contrast(0.8)
                .brightness(-0.1)
                .drawingGroup(opaque: true)
                .ignoresSafeArea()
                .animation(.default, value: controller.selectedGroup?.id)
        }
    }

}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
