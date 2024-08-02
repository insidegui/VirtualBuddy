//
//  RestoreImagePicker.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import VirtualCore
import Combine

final class RestoreImagePickerController: ObservableObject {

    let library: VMLibraryController

    init(library: VMLibraryController) {
        self.library = library
    }

    private lazy var api = VBAPIClient()
    
    @Published private(set) var catalog: ResolvedCatalog?
    @Published var selectedGroup: ResolvedCatalogGroup?
    @Published var selectedRestoreImage: ResolvedRestoreImage?
    @Published var errorMessage: String?

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

struct RestoreImagePicker: View {
    @StateObject private var controller: RestoreImagePickerController

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
        self._controller = .init(wrappedValue: RestoreImagePickerController(library: library))
        self._selection = selection
        self.guestType = guestType
        self.validationChanged = validationChanged
        self.onUseLocalFile = onUseLocalFile
        self.authRequirementFlow = authRequirementFlow
    }

    var body: some View {
        CatalogGroupPicker(groups: controller.catalog?.groups ?? [], selectedGroup: $controller.selectedGroup)
            .task { controller.loadRestoreImageOptions(for: guestType) }

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
    private func advisoryView(with advisory: RestoreImagePickerController.Advisory) -> some View {
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

#if DEBUG
struct RestoreImagePicker_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }
    
    struct _Template: View {
        @State private var image: ResolvedRestoreImage?
        
        var body: some View {
            RestoreImagePicker(
                library: .preview,
                selection: $image,
                guestType: .mac,
                validationChanged: PassthroughSubject<Bool, Never>()
            )
        }
    }
}
#endif
