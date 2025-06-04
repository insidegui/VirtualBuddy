import SwiftUI
import VirtualCore
import Combine

enum RestoreImageSelectionFocus: Hashable {
    case groups
    case images
}

final class RestoreImageSelectionController: ObservableObject {

    let library: VMLibraryController

    init(library: VMLibraryController) {
        self.library = library

        $selectedGroup.removeDuplicates().sink { [weak self] group in
            guard let self else { return }
            guard let group else { return }

            guard selectedRestoreImage?.image.group != group.id else { return }

            /// Selected group has changed, update available channel groups, images, and selected image.
            let updatedChannelGroups = ChannelGroup.groups(with: group.restoreImages)
            channelGroups = updatedChannelGroups
            images = updatedChannelGroups.flatMap(\.images)
            selectedRestoreImage = updatedChannelGroups.first?.images.first
        }
        .store(in: &cancellables)
    }

    private lazy var api = VBAPIClient()

    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var catalog: ResolvedCatalog?
    @Published private(set) var channelGroups: [ChannelGroup] = []
    @Published private(set) var images: [ResolvedRestoreImage] = []
    @Published var selectedGroup: ResolvedCatalogGroup?
    @Published var selectedRestoreImage: ResolvedRestoreImage?
    @Published var errorMessage: String?
    @Published var focusedElement = RestoreImageSelectionFocus.groups

    func loadRestoreImageOptions(for guest: VBGuestType) {
        Task {
            do {
                let catalog = try await api.fetchRestoreImages(for: guest)
                let platform: CatalogGuestPlatform = guest == .linux ? .linux : .mac
                let resolved = try ResolvedCatalog(environment: .current.guest(platform: platform), catalog: catalog)

                await MainActor.run {
                    self.selectedGroup = resolved.groups.first
                    self.catalog = resolved
                }
            } catch {
                await MainActor.run {
                    self.catalog = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension ChannelGroup {
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
