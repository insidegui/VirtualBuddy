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
            CatalogGroupPicker(groups: controller.catalog?.groups ?? [], selectedGroup: $controller.selectedGroup)

            if let catalog = controller.catalog, let group = controller.selectedGroup {
                RestoreImageBrowser(catalog: catalog, group: group, selection: $viewModel.data.resolvedRestoreImage)
            }
        }
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

struct BlurHashFullBleedBackground: View {
    var blurHash: BlurHashToken?

    init(_ blurHash: BlurHashToken?) {
        self.blurHash = blurHash
    }

    init(_ blurHashValue: String?) {
        self.blurHash = blurHashValue.flatMap { BlurHashToken(value: $0) }
    }

    var body: some View {
        if let blurHash {
            Image(blurHash: blurHash)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 22, opaque: true)
                .saturation(1.3)
                .contrast(0.8)
                .brightness(-0.1)
                .drawingGroup(opaque: true)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.default, value: blurHash)
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
