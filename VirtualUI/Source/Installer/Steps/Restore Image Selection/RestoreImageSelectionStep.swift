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
    @StateObject private var controller: RestoreImageSelectionController

    @ObservedObject var library: VMLibraryController
    @Binding var selection: ResolvedRestoreImage?
    var guestType: VBGuestType
    var validationChanged: PassthroughSubject<Bool, Never>
    var onUseLocalFile: (URL) -> Void = { _ in }

    init(library: VMLibraryController,
         selection: Binding<ResolvedRestoreImage?>,
         guestType: VBGuestType,
         validationChanged: PassthroughSubject<Bool, Never>,
         onUseLocalFile: @escaping (URL) -> Void = { _ in },
         authRequirementFlow: VBGuestReleaseChannel.Authentication? = nil)
    {
        self._library = .init(initialValue: library)
        self._controller = .init(wrappedValue: RestoreImageSelectionController(library: library))
        self._selection = selection
        self.guestType = guestType
        self.validationChanged = validationChanged
        self.onUseLocalFile = onUseLocalFile
        self.authRequirementFlow = authRequirementFlow
    }

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.installationWizardMaxContentWidth)
    private var maxContentWidth

    private var browserInsetTop: CGFloat { 100 }

    var body: some View {
        HStack(spacing: 0) {
            CatalogGroupPicker(groups: controller.catalog?.groups ?? [], selectedGroup: $controller.selectedGroup)

            if let catalog = controller.catalog, let group = controller.selectedGroup {
                RestoreImageBrowser(catalog: catalog, group: group, selection: $selection)
            }
        }
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
        .background { colorfulBackground }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(controller)
        .task { controller.loadRestoreImageOptions(for: guestType) }
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

    @State private var authRequirementFlow: VBGuestReleaseChannel.Authentication?

}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
