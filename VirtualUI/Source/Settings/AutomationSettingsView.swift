//
//  AutomationSettingsView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/06/25.
//

import SwiftUI
import VirtualCore
import BuddyKit
import DeepLinkSecurity

struct AutomationSettingsView: View {
    @EnvironmentObject private var sentinel: DeepLinkSentinel

    private var store: DeepLinkManagementStore { sentinel.managementStore }

    @State private var descriptors = [DeepLinkClientDescriptor]()

    var body: some View {
        Form {
            Section {
                if descriptors.isEmpty {
                    Text("Apps that try to control VirtualBuddy will show up here.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(descriptors) { descriptor in
                        Toggle(isOn: toggleBinding(for: descriptor)) {
                            Label {
                                Text(descriptor.displayName)
                            } icon: {
                                Image(nsImage: descriptor.icon.image)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                    }
                }
            } header: {
                Text("Allow Apps to Control VirtualBuddy")
            } footer: {
                if !descriptors.isEmpty {
                    SettingsFooter {
                        Text("""
                        These apps have previously tried to open a deep link in VirtualBuddy.
                        
                        When an app tries to open a deep link in VirtualBuddy for the first time, you'll be asked to grant permission. \
                        Once you've allowed it, the app can open deep links without asking again.
                        """)
                    }
                }
            }
        }
        .task {
            for await descriptors in store.clientDescriptors() {
                self.descriptors = descriptors
            }
        }
        .navigationTitle(Text("Automation"))
    }

    private func toggleBinding(for descriptor: DeepLinkClientDescriptor) -> Binding<Bool> {
        .init {
            descriptor.authorization == .authorized
        } set: { granted in
            Task { @MainActor in
                do {
                    try await sentinel.setAuthorization(granted ? .authorized : .denied, for: descriptor)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
final class PreviewDeepLinkAuthUI: DeepLinkAuthUI {
    func presentDeepLinkAuth(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        return .authorized
    }
}

extension DeepLinkSentinel {
    static let preview: DeepLinkSentinel = {
        let s = DeepLinkSentinel(
            authUI: PreviewDeepLinkAuthUI(),
            authStore: MemoryDeepLinkAuthStore(),
            managementStore: UserDefaultsDeepLinkManagementStore(namespace: "preview", inMemory: true)
        )

        Task {
            do {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: "/System/Applications"), includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]) else {
                    throw Failure("Can't enumerate /System/Applications")
                }

                while let url = enumerator.nextObject() as? URL {
                    guard (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .application) == true else { continue }

                    let auth: DeepLinkClientAuthorization = Int.random(in: 0...1024) % 2 == 0 ? .authorized : .denied

                    guard let client = try? DeepLinkClient(url: url) else { continue }
                    try? await s.authStore.setAuthorization(auth, for: client)
                    let descriptor = DeepLinkClientDescriptor(client: client, authorization: auth)
                    try? await s.managementStore.insert(descriptor)
                }

            } catch {
                print("Error populating preview sentinel: \(error)")
            }
        }

        return s
    }()
}

#Preview("Automation Settings") {
    SettingsScreen.preview(.automation)
}
#endif
