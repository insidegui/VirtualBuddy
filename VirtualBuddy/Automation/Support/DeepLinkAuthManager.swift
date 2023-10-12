import SwiftUI
import DeepLinkSecurity

@available(macOS 13.0, *)
struct DeepLinkAuthManager: View {
    var sentinel: DeepLinkSentinel

    init(sentinel: DeepLinkSentinel) {
        self.sentinel = sentinel
    }

    private var store: DeepLinkManagementStore { sentinel.managementStore }

    @State private var descriptors = [DeepLinkClientDescriptor]()

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

#if DEBUG
@available(macOS 13.0, *)
#Preview {
    DeepLinkAuthManager(sentinel: DeepLinkHandler.shared.sentinel)
}
#endif
