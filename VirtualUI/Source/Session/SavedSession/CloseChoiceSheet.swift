import SwiftUI
import VirtualCore

/// Introduces saving the state of a virtual machine and asks what closing it should do.
struct CloseChoiceSheet: View {
    struct Result {
        var choice: SessionCloseChoice
        var makeDefault: Bool
    }

    /// The virtual machines this applies to. A single name when closing a window, several when quitting.
    var machines: [String]
    var isQuitting: Bool
    var onFinish: (Result?) -> Void

    @State private var makeDefault = false

    private var subtitle: String {
        if isQuitting {
            if machines.count == 1, let name = machines.first {
                return "“\(name)” is running."
            }
            return "\(machines.count) virtual machines are running: \(machines.formatted(.list(type: .and)))."
        } else {
            return "“\(machines.first ?? "")” is running."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(spacing: 10) {
                ChoiceCard(
                    symbol: "tray.and.arrow.down.fill",
                    tint: .accentColor,
                    title: "Save State",
                    badge: "Recommended",
                    detail: "Pick up exactly where you left off. Open apps and unsaved work are kept, and starting again resumes in moments.",
                    isDefault: true
                ) {
                    onFinish(Result(choice: .saveState, makeDefault: makeDefault))
                }

                ChoiceCard(
                    symbol: "power",
                    tint: .secondary,
                    title: "Shutdown",
                    badge: nil,
                    detail: "Ask the guest to shut down normally. Next time, the virtual machine starts up from scratch.",
                    isDefault: false
                ) {
                    onFinish(Result(choice: .shutDown, makeDefault: makeDefault))
                }
            }

            Text("A saved state stays with the virtual machine on this Mac. Shared folders and network connections aren’t preserved, and a saved state may stop working after macOS or VirtualBuddy updates. To keep a particular state around, duplicate the saved virtual machine before resuming it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .center) {
                Toggle(isOn: $makeDefault) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Always do this")
                        Text("You can change it later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel") {
                    onFinish(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Close now. Continue later.")
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ChoiceCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var badge: String?
    var detail: String
    var isDefault: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)

                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isDefault ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: isDefault ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Presentation

/// Lets the view hosted in a sheet finish the sheet it's in.
private final class SheetFinishBox<Output> {
    var finish: ((Output?) -> Void)?
}

@MainActor
extension SavedSessionPrompts {
    /// Presents a SwiftUI view as a sheet on the window, or in a window of its own when there's no window to attach to.
    /// - Returns: What the view finished with. Closing the view without finishing returns `nil`.
    static func presentSheet<Output, Content: View>(
        from window: NSWindow?,
        @ViewBuilder content: (_ finish: @escaping (Output?) -> Void) -> Content
    ) async -> Output? {
        await withCheckedContinuation { continuation in
            let box = SheetFinishBox<Output>()
            let hosting = NSHostingController(rootView: content { box.finish?($0) })
            hosting.sizingOptions = [.preferredContentSize]

            let sheetWindow = NSWindow(contentViewController: hosting)
            sheetWindow.styleMask = [.titled, .fullSizeContentView]
            sheetWindow.titlebarAppearsTransparent = true
            sheetWindow.isReleasedWhenClosed = false

            let parent = window.flatMap { $0.isVisible ? $0 : nil }

            var isFinished = false

            box.finish = { output in
                guard !isFinished else { return }
                isFinished = true
                box.finish = nil

                if let parent {
                    parent.endSheet(sheetWindow)
                }
                sheetWindow.orderOut(nil)
                sheetWindow.contentViewController = nil

                continuation.resume(returning: output)
            }

            if let parent {
                parent.beginSheet(sheetWindow)
            } else {
                sheetWindow.level = .floating
                sheetWindow.center()
                sheetWindow.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }
}

#if DEBUG
#Preview("Close") {
    CloseChoiceSheet(machines: ["macOS 27 Hackable"], isQuitting: false) { _ in }
}

#Preview("Quit") {
    CloseChoiceSheet(machines: ["macOS 27 Hackable", "Sequoia Test"], isQuitting: true) { _ in }
}
#endif
