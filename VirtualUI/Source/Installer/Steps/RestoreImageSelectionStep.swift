//
//  RestoreImageSelectionStep.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

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
    }

    private lazy var api = VBAPIClient()
    
    @Published private(set) var catalog: ResolvedCatalog?
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

    enum Advisory: Hashable {
        case manualDownloadTip(_ title: String, _ url: URL)
        case alreadyDownloaded(_ title: String, _ localURL: URL)
        case failure(_ message: String)
    }

    @MainActor
    func restoreAdvisory(for image: ResolvedRestoreImage) -> Advisory? {
        do {
            if let existingDownloadURL = try library.existingLocalURL(for: image.url) {
                return .alreadyDownloaded(image.name, existingDownloadURL)
            } else {
                return .manualDownloadTip(image.name, image.url)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    
}

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

    private var browserInsetTop: CGFloat { 100 }

    var body: some View {
        HStack(spacing: 0) {
            CatalogGroupPicker(groups: controller.catalog?.groups ?? [], selectedGroup: $controller.selectedGroup)

            if let catalog = controller.catalog, let group = controller.selectedGroup {
                RestoreImageBrowser(catalog: catalog, group: group, selection: $selection)
            }
        }
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
        }
    }

    @ViewBuilder
    private var advisories: some View {
        if let selectedImage = controller.selectedRestoreImage,
           let advisory = controller.restoreAdvisory(for: selectedImage)
        {
            advisoryView(with: advisory)
        }

        if VBAPIClient.Environment.current != .production {
            Text("Notice: API environment override from defaults/arguments. Using API URL: \(VBAPIClient.Environment.current.baseURL)")
                .font(.caption)
                .foregroundColor(.yellow)
        }
    }

    @ViewBuilder
    private func advisoryView(with advisory: RestoreImageSelectionController.Advisory) -> some View {
        VStack {
            switch advisory {
            case .manualDownloadTip(let title, let url):
                Text("""
                     If you prefer to use a download manager, you may download \(title) from the following URL:

                     \(url)
                     """)
                .foregroundColor(.secondary)
            case .alreadyDownloaded(let title, let localURL):
                VStack {
                    Text("\(title) is already downloaded. Click \"Continue\" below to re-download it or proceed with the installation right now by using the previously downloaded image.")
                        .foregroundColor(.green)

                    Button("Install Now") { onUseLocalFile(localURL) }
                        .controlSize(.large)
                }
            case .failure(let error):
                Text("VirtualBuddy couldn't create its downloads directory within \(library.libraryURL.path): \(error)")
                    .foregroundColor(.red)
            }
        }
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .padding(.top)
    }
    
    @State private var authRequirementFlow: VBGuestReleaseChannel.Authentication?

}
