//
//  RestoreImageBrowser.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 02/08/24.
//

import SwiftUI
import VirtualCore

struct ChannelGroup: Identifiable, Hashable {
    var id: CatalogChannel.ID { channel.id }
    var channel: CatalogChannel
    var images: [ResolvedRestoreImage]
}

struct RestoreImageBrowser: View {
    var catalog: ResolvedCatalog
    var group: ResolvedCatalogGroup
    var channelGroups: [ChannelGroup]
    @Binding var selection: ResolvedRestoreImage?

    init(catalog: ResolvedCatalog, group: ResolvedCatalogGroup, selection: Binding<ResolvedRestoreImage?>) {
        self.catalog = catalog
        self.group = group
        self.channelGroups = ChannelGroup.groups(with: group.restoreImages)
        self._selection = selection
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
                ForEach(channelGroups) { group in
                    Section {
                        ForEach(group.images) { image in
                            Text(image.name)
                                .tag(image)
                        }
                    } header: {
                        Text(group.channel.name)
                    }
                }
            }
        }
    }
}

private extension ChannelGroup {
    static func groups(with restoreImages: [ResolvedRestoreImage]) -> [ChannelGroup] {
        var groupsByChannel = [CatalogChannel: ChannelGroup]()

        for image in restoreImages {
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
    RestoreImageBrowser(catalog: .previewMac, group: ResolvedCatalog.previewMac.groups[1], selection: $selection)
}
#endif
