import SwiftUI
import VirtualCore
import Combine
import OSLog

enum RestoreImageSelectionFocus: Hashable {
    case groups
    case images
}

@MainActor
final class RestoreImageSelectionController: ObservableObject {

    /// If loading takes less than this amount of time, then the controller will never even set the `isLoading` property.
    private static let minLoadingTimeInMilliseconds = 100

    private let logger = Logger(subsystem: VirtualUIConstants.subsystemName, category: String(describing: RestoreImageSelectionController.self))

    init() {
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

    @Published private(set) var isLoading = false {
        didSet {
            if !isLoading {
                deferredLoadingTask?.cancel()
                deferredLoadingTask = nil
            }
        }
    }

    /// The controller will only set the`isLoading` property if loading takes a while.
    private var deferredLoadingTask: Task<Void, Never>?
    private func deferredStartLoading() {
        deferredLoadingTask?.cancel()
        deferredLoadingTask = Task { [weak self] in
            guard let self else { return }

            defer { deferredLoadingTask = nil }

            do {
                try await Task.sleep(for: .milliseconds(Self.minLoadingTimeInMilliseconds))

                logger.debug("Reached loading time delay, setting isLoading.")

                isLoading = true
            } catch { }
        }
    }

    func loadRestoreImageOptions(for guest: VBGuestType) {
        logger.debug("Loading restore image options.")

        deferredStartLoading()

        Task {
            let start = ContinuousClock.now

            defer {
                logger.debug("Loading restore images took \(start.duration(to: .now).formatted(.units(allowed: [.milliseconds])), privacy: .public)")

                isLoading = false
            }

            do {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "VBSimulateSlowCatalogFetch") {
                    logger.notice("⚠️ Delaying restore image options load due to VBSimulateSlowCatalogFetch debug flag!")
                    try await Task.sleep(for: .seconds(2))
                }
                #endif

                let catalog = try await api.fetchRestoreImages(for: guest)
                let platform: CatalogGuestPlatform = guest == .linux ? .linux : .mac
                let resolved = try ResolvedCatalog(environment: .current.guest(platform: platform), catalog: catalog)

                await MainActor.run {
                    self.selectedGroup = resolved.groups.first
                    self.catalog = resolved
                }
            } catch {
                logger.error("Loading restore images failed - \(error, privacy: .public)")
                
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
