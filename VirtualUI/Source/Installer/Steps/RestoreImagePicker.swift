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

    @EnvironmentObject private var library: VMLibraryController

    private lazy var api = VBAPIClient()
    
    @Published private(set) var restoreImageOptions: [VBRestoreImageInfo] = []
    @Published var selectedRestoreImage: VBRestoreImageInfo?
    @Published var errorMessage: String?
    @Published var cookie: String?
    
    func loadRestoreImageOptions(for guest: VBGuestType) {
        Task {
            do {
                let images = try await api.fetchRestoreImages(for: guest)
                
                await MainActor.run {
                    self.restoreImageOptions = images
                }
            } catch {
                await MainActor.run {
                    self.restoreImageOptions = []
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func validateSelectedRestoreImage() -> Bool {
        if let info = selectedRestoreImage {
            if info.needsCookie, cookie == nil {
                return false
            } else {
                return true
            }
        } else {
            return selectedRestoreImage != nil
        }
    }
    
    enum Advisory: Hashable {
        case manualDownloadTip(_ title: String, _ url: URL)
        case alreadyDownloaded(_ title: String, _ localURL: URL)
        case failure(_ message: String)
    }

    @MainActor
    func restoreAdvisory(for info: VBRestoreImageInfo) -> Advisory? {
        do {
            if let existingDownloadURL = try library.existingLocalURL(for: info.url) {
                return .alreadyDownloaded(info.name, existingDownloadURL)
            } else {
                return .manualDownloadTip(info.name, info.url)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    
}

struct RestoreImagePicker: View {
    @EnvironmentObject private var library: VMLibraryController
    @StateObject var controller = RestoreImagePickerController()

    @Binding var selection: VBRestoreImageInfo?
    var guestType: VBGuestType
    var validationChanged: PassthroughSubject<Bool, Never>
    var onUseLocalFile: (URL) -> Void = { _ in }

    var body: some View {
        Picker("OS Version", selection: $controller.selectedRestoreImage) {
            if controller.restoreImageOptions.isEmpty {
                Text("Loading…")
                    .tag(Optional<VBRestoreImageInfo>.none)
            } else {
                Text("Choose")
                    .tag(Optional<VBRestoreImageInfo>.none)

                ForEach(controller.restoreImageOptions) { option in
                    Text(option.name)
                        .tag(Optional<VBRestoreImageInfo>.some(option))
                }
            }
        }
        .controlSize(.large)
        .disabled(controller.restoreImageOptions.isEmpty)
        .onChange(of: controller.selectedRestoreImage, perform: {
            selection = $0
            validationChanged.send(controller.validateSelectedRestoreImage())
        })
        .onAppearOnce { controller.loadRestoreImageOptions(for: guestType) }

        if let selectedImage = controller.selectedRestoreImage,
           let advisory = controller.restoreAdvisory(for: selectedImage)
        {
            advisoryView(with: advisory)
        }

        if let authRequirement = selection?.authenticationRequirement {
            authenticationEntryPoint(with: authRequirement)
                .padding(.top, 36)
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

    @ViewBuilder
    private func authenticationEntryPoint(with requirement: VBGuestReleaseChannel.Authentication) -> some View {
        VStack(spacing: 16) {
            Text(requirement.note)
                .font(.system(size: 12))
                .lineSpacing(1.2)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                if controller.cookie == nil {
                    Button("Sign In…") {
                        authRequirementFlow = requirement
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)

                        Text("Authenticated")
                            .font(.system(size: 15, weight: .medium))
                    }

                    Button("Change Account…") {
                        authRequirementFlow = requirement
                    }
                }
            }
        }
        .controlSize(.large)
        .multilineTextAlignment(.center)
        .sheet(item: $authRequirementFlow, content: { requirement in
            AuthenticatingWebView(url: requirement.url) { cookies in
                guard let headerValue = requirement.satisfiedCookieHeaderValue(with: cookies) else { return }
                self.controller.cookie = headerValue
                self.authRequirementFlow = nil
            }
            .frame(minWidth: 500, maxWidth: .infinity, minHeight: 550, maxHeight: .infinity)
        })
    }
}

#if DEBUG
struct RestoreImagePicker_Previews: PreviewProvider {
    static var previews: some View {
        _Template()
    }
    
    struct _Template: View {
        @State private var image: VBRestoreImageInfo?
        
        var body: some View {
            RestoreImagePicker(selection: $image, guestType: .mac, validationChanged: PassthroughSubject<Bool, Never>())
        }
    }
}
#endif
