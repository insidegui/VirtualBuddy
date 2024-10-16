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
    var channelGroups: [ChannelGroup]
    private var images: [ResolvedRestoreImage]
    @Binding var selection: ResolvedRestoreImage?

    init(catalog: ResolvedCatalog, group: ResolvedCatalogGroup, selection: Binding<ResolvedRestoreImage?>) {
        self.catalog = catalog
        self.group = group
        let groups = ChannelGroup.groups(with: group.restoreImages)
        self.channelGroups = groups
        self.images = groups.flatMap(\.images)
        self._selection = selection
    }

    @Environment(\.containerPadding)
    private var containerPadding

    @FocusState private var focused: Bool

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
                ForEach(channelGroups) { group in
                    section(for: group)
                }
            }
            .padding(.horizontal, containerPadding)
        }
        .focusable()
        .focused($focused)
        .backported_focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .down:
                if let previous = images.next(from: selection) {
                    selection = previous
                }
            case .up:
                if let next = images.previous(from: selection) {
                    selection = next
                } else {
                    focused = false
                }
            default:
                break
            }
        }
        .onReceive(controller.$focusedElement) { element in
            guard element == .images else { return }

            self.focused = true

            if selection == nil {
                selection = images.first
            }
        }
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThin, in: shape)
            .background(Color.black.opacity(0.14).blendMode(.plusDarker), in: shape)
            .overlay {
                if isSelected {
                    shape
                        .strokeBorder(Color.white, lineWidth: 2)
                }
            }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }
}

extension ResolvedRestoreImage {
    var formattedDownloadSize: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
    }
}

private extension ChannelGroup {
    static func groups(with restoreImages: [ResolvedRestoreImage]) -> [ChannelGroup] {
        var groupsByChannel = [CatalogChannel: ChannelGroup]()

        let sortedImages = restoreImages.sorted(by: { $0.build > $1.build })

        for image in sortedImages {
            groupsByChannel[image.channel, default: ChannelGroup(channel: image.channel, images: [])]
                .images.append(image)
        }

        /// Place regular releases above developer betas.
        return groupsByChannel.values.sorted {
            $0.id == "regular" && $1.id == "devbeta"
        }
    }
}

#if DEBUG
@available(macOS 14.0, *)
#Preview {
    @Previewable @State var selection: ResolvedRestoreImage?
    RestoreImageBrowser(catalog: .previewMac, group: ResolvedCatalog.previewMac.groups[0], selection: $selection)
}
#endif
