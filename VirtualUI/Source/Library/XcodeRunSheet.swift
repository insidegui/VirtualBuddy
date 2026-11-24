import AppKit
import SwiftUI

/// Run operations share the same window chrome, content margins and action placement.
@MainActor
final class XcodeRunPanel: NSPanel {
    private weak var presentationParent: NSWindow?

    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        self.title = title
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    func host(_ content: some View) {
        // As the panel's content view, the hosting view supplies its size constraints
        // directly to AppKit, including when the provisioning form changes height.
        let view = NSHostingView(rootView: content)
        contentView = view
        setContentSize(view.fittingSize)
    }

    func present(for destination: UUID) {
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        if let session = VirtualMachineSessionUIManager.shared.sessions.values.first(where: { $0.virtualMachine.uuid == destination }),
           let window = session.hostWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            session.bringToFront()
            presentationParent = window
            window.beginSheet(self)
        } else {
            isMovableByWindowBackground = true
            center()
            makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        if let sheet = attachedSheet { endSheet(sheet, returnCode: .cancel) }
        presentationParent?.endSheet(self)
        presentationParent = nil
        orderOut(nil)
        contentView = nil
        close()
    }
}

struct XcodeRunSheet<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .vertical) {
                    rows.fixedSize(horizontal: false, vertical: true)
                    ScrollView { rows }.scrollBounceBehavior(.basedOnSize).frame(height: 330)
                }
                .frame(maxHeight: 330)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)

            HStack(spacing: 10) { actions }
                .controlSize(.large)
                .padding(20)
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct XcodeRunRow<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 25, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                content.foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
#Preview("Run Sheet") {
    XcodeRunSheet(title: "Provision App for Debugging",
                  subtitle: "The development profile must include your Test Mac.") {
        XcodeRunRow(symbol: "person.2", title: "Signing Team EXAMPLE123") {
            Text(verbatim: "com.example.FieldNotes")
        }
    } actions: {
        Spacer()
        Button("Cancel", role: .cancel) {}.airGlassButtonStyle()
        Button("Refresh Profiles") {}.airGlassButtonStyle(prominent: true)
    }
}

#Preview("Run Sheet Row") {
    XcodeRunRow(symbol: "desktopcomputer", title: "Provisioning UDID") {
        Text(verbatim: "0123456789abcdef0123456789abcdef01234567")
            .font(.callout.monospaced())
    }
    .padding()
    .frame(width: 480)
}
#endif
