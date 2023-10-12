import SwiftUI
import DeepLinkSecurity

final class DeepLinkAuthPanel: NSPanel {

    private static var panelInstances = NSHashTable<NSPanel>(options: [.strongMemory, .objectPointerPersonality])

    @MainActor
    static func run(for request: OpenDeepLinkRequest) async throws -> DeepLinkClientAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let panel = DeepLinkAuthPanel(request: request) { panelInstance, decision in
                defer { panelInstances.remove(panelInstance) }

                continuation.resume(returning: decision)

                panelInstance.close()
            }

            panelInstances.add(panel)

            panel.makeKeyAndOrderFront(nil)
            panel.center()
        }
    }

    private init(request: OpenDeepLinkRequest, completion: @escaping (DeepLinkAuthPanel, DeepLinkClientAuthorization) -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless, .titled, .fullSizeContentView], backing: .buffered, defer: false)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .alertPanel
        let dialog = DeepLinkAuthDialog(request: request) { [weak self] granted in
            guard let self = self else { return }
            completion(self, granted ? .authorized : .denied)
        }
        contentViewController = NSHostingController(rootView: dialog)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

}

struct DeepLinkAuthDialog: View {
    var request: OpenDeepLinkRequest
    var response: (Bool) -> Void

    private var appName: String
    private var appIcon: Image

    init(request: OpenDeepLinkRequest, response: @escaping (Bool) -> Void) {
        self.request = request
        self.response = response
        self.appName = request.client.displayName
        self.appIcon = Image(nsImage: request.client.icon.image)
    }

    private var iconContainerSize: CGFloat { 58 }
    private var handIconSizeMultiplier: CGFloat { 0.5 }
    private var appIconSizeMultiplier: CGFloat { 0.432 }

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: iconContainerSize, height: iconContainerSize)
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color.white)
                    .imageScale(.large)
                    .font(.system(size: iconContainerSize * handIconSizeMultiplier, weight: .medium, design: .rounded))
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0.5, y: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            .overlay(alignment: .bottomTrailing) {
                appIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconContainerSize * appIconSizeMultiplier, height: iconContainerSize * appIconSizeMultiplier)
                    .offset(x: 8, y: 8)
            }

            Text("\"\(appName)\" would like to access and control your virtual machines in VirtualBuddy.")
                .lineLimit(nil)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button(role: .cancel) {
                    response(false)
                } label: {
                    Text("Don't Allow")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    response(true)
                } label: {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(minWidth: 260, minHeight: 230)
    }
}

#if DEBUG
extension DeepLinkClient {
    static let preview = DeepLinkClient(
        url: URL(fileURLWithPath: "/System/Applications/Notes.app"),
        designatedRequirement: "identifier \"com.apple.Notes\" and anchor apple"
    )
}

extension DeepLinkClientDescriptor {
    static let preview = DeepLinkClientDescriptor(client: .preview)
}

extension OpenDeepLinkRequest {
    static let preview = OpenDeepLinkRequest(url: URL(string: "x-test-link-auth://test1")!, client: .preview)
}

#Preview {
    DeepLinkAuthDialog(request: .preview) { response in
        print("Response: \(response)")
    }
    .frame(width: 320)
}
#endif
