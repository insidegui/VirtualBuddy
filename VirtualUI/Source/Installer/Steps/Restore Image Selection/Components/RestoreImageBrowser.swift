//
//  RestoreImageBrowser.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 02/08/24.
//

import SwiftUI
import VirtualCore
import Combine

struct ChannelGroup: Identifiable, Hashable {
    var id: CatalogChannel.ID { channel.id }
    var channel: CatalogChannel
    var images: [ResolvedRestoreImage]
}

struct RestoreImageBrowser: View {
    @EnvironmentObject
    private var controller: RestoreImageSelectionController

    var catalog: ResolvedCatalog
    var group: ResolvedCatalogGroup
    @Binding var selection: ResolvedRestoreImage?

    init(catalog: ResolvedCatalog, group: ResolvedCatalogGroup, selection: Binding<ResolvedRestoreImage?>) {
        self.catalog = catalog
        self.group = group
        self._selection = selection
    }

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.installationWizardMaxContentWidth)
    private var maxContentWidth

    @FocusState
    private var focus: RestoreImageSelectionFocus?

    @State private var scrolledImageID: ResolvedRestoreImage.ID?

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                scrollView
                    .scrollPosition(id: $scrolledImageID, anchor: .center)
            } else {
                scrollView
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: containerPadding) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: containerPadding) }
        .focusable()
        .focused($focus, equals: RestoreImageSelectionFocus.images)
        .backported_focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .down:
                if let previous = controller.images.next(from: controller.selectedRestoreImage) {
                    controller.selectedRestoreImage = previous
                }
            case .up:
                if let next = controller.images.previous(from: controller.selectedRestoreImage) {
                    controller.selectedRestoreImage = next
                }
            case .left:
                controller.focusedElement = .groups
            default:
                break
            }
        }
        .onChange(of: selection?.id) { id in
            scrolledImageID = id
        }
        .onReceive(controller.$focusedElement) { focus = $0 }
        .onReceive(controller.$selectedRestoreImage.removeDuplicates()) {
            guard let newSelection = $0 else { return }
            guard newSelection.id != selection?.id else { return }
            guard newSelection.image.group == group.id else { return }

            selection = $0
        }
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if #available(macOS 14.0, *) {
                stack.scrollTargetLayout()
            } else {
                stack
            }
        }
    }

    @ViewBuilder
    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
            ForEach(controller.channelGroups) { group in
                section(for: group)
            }
        }
        .padding(.trailing, containerPadding)
        .padding(.leading, containerPadding * 0.5)
    }

    @ViewBuilder
    private func section(for group: ChannelGroup) -> some View {
        Section {
            ForEach(group.images) { image in
                RestoreImageButton(image: image, isSelected: image.id == selection?.id) {
                    selection = image
                }
                .tag(image)
            }
        }
    }
}

private struct RestoreImageButton: View {
    var image: ResolvedRestoreImage
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            label
        }
        .buttonStyle(RestoreImageButtonStyle(isSelected: isSelected))
    }

    @ViewBuilder
    var label: some View {
        HStack {
            HStack {
                Image(systemName: image.channel.icon)
                    .foregroundStyle(.secondary)
                
                Text(image.name)
            }
                .font(.headline)

            Spacer()

            HStack(spacing: 4) {
                Text(image.build)

                Text("·")

                Text(image.formattedDownloadSize)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .monospacedDigit()
    }
}

struct RestoreImageButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = 14

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.thin, in: shape)
            .background(Color.black.opacity(0.14).blendMode(.plusDarker), in: shape)
            .chromeBorder(radius: cornerRadius, highlightEnabled: !isSelected, shadowEnabled: false, highlightIntensity: 0.4)
            .overlay {
                if isSelected {
                    shape
                        .strokeBorder(Color.white, lineWidth: 2)
                        .blendMode(.plusLighter)
                        .opacity(isFocused ? 0.8 : 0.4)
                }
            }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension ResolvedRestoreImage {
    var formattedDownloadSize: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
    }
}

#if DEBUG
@available(macOS 14.0, *)
#Preview {
    @Previewable @State var selection: ResolvedRestoreImage?
    RestoreImageBrowser(catalog: .previewMac, group: ResolvedCatalog.previewMac.groups[0], selection: $selection)
}
#endif
