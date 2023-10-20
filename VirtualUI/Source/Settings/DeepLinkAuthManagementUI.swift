import SwiftUI
import DeepLinkSecurity

#if DEBUG
import VirtualCore
import UniformTypeIdentifiers
#endif

@available(macOS 13.0, *)
struct DeepLinkAuthManagementUI: View {
    var sentinel: DeepLinkSentinel

    init(sentinel: DeepLinkSentinel) {
        self.sentinel = sentinel
    }

    private var store: DeepLinkManagementStore { sentinel.managementStore }

    @Environment(\.dismiss)
    private var dismiss

    @State private var descriptors = [DeepLinkClientDescriptor]()

    @State private var showingExpandedHelp = false

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apps Allowed to Control VirtualBuddy")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("The apps listed below have previously attempted to open a deep link in VirtualBuddy.")
                            .foregroundStyle(.secondary)
                        if !showingExpandedHelp {
                            Button("More…") {
                                showingExpandedHelp = true
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if showingExpandedHelp {
                        Text("""
                        The first time an app attempts to open a deep link in VirtualBuddy, \
                        you will be prompted to allow the app to perform the action. After an app is allowed to open a deep link in VirtualBuddy, \
                        it may then open deep links without a permission prompt.
                        """)
                        .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Material.regular, in: Rectangle())
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Material.regular, in: Rectangle())
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .task {
            for await descriptors in store.clientDescriptors() {
                self.descriptors = descriptors
            }
        }
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

@available(macOS 13.0, *)
#Preview {
    DeepLinkAuthManagementUI(sentinel: .preview)
}
#endif
