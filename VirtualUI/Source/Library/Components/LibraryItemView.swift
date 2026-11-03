//
//  LibraryItemView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 21/07/22.
//

import SwiftUI
import VirtualCore
import BuddyFoundation

public extension EnvironmentValues {
    /// This is injected by reading from ``VBSettings``.
    /// When `true`, virtual machine thumbnails in the library show the actual desktop picture thumbnail instead of the blurred version.
    @Entry var virtualBuddyShowDesktopPictureThumbnails = false
}

/// This button style achieves a couple of things:
/// - Gives its label a `vbLibraryButtonPressed` environment value that can be used to react to button presses
/// - Fixes an annoying behavior common to all standard SwiftUI button styles where pressing the space bar
/// with one of its subviews in focus would trigger the button's action instead of entering a space in a text field, for example
struct VBLibraryItemButtonStyle: PrimitiveButtonStyle {

    @State private var isPressed = false

    /// The rectangle of the button's contents in the local coordinate space.
    @State private var rect: CGRect = .zero

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.vbLibraryButtonPressed, isPressed)
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: VBLibraryButtonSizePreferenceKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(VBLibraryButtonSizePreferenceKey.self) { rect = CGRect(origin: .zero, size: $0) }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { value in
                /// Replicate standard button behavior where dragging outside the button cancels the click.
                isPressed = rect.contains(value.location)
            }.onEnded { _ in
                /// If the button is not currently pressed, then don't perform the action.
                guard isPressed else { return }

                configuration.trigger()

                isPressed = false
            })
    }

}

struct VBLibraryButtonSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension PrimitiveButtonStyle where Self == VBLibraryItemButtonStyle {
    static var vbLibraryItem: VBLibraryItemButtonStyle { VBLibraryItemButtonStyle() }
}

private struct VBLibraryItemButtonPressedEnvironmentKey: EnvironmentKey {
    static var defaultValue = false
}
private extension EnvironmentValues {
    var vbLibraryButtonPressed: VBLibraryItemButtonPressedEnvironmentKey.Value {
        get { self[VBLibraryItemButtonPressedEnvironmentKey.self] }
        set { self[VBLibraryItemButtonPressedEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct LibraryItemView: View {

    @EnvironmentObject var library: VMLibraryController
    @EnvironmentObject var sessionManager: VirtualMachineSessionUIManager

    var vm: VBVirtualMachine
    @State var name: String

    @Environment(\.vbLibraryButtonPressed)
    private var isPressed

    var nameFieldFocus = BoolSubject()

    @State private var configurationVM: VBVirtualMachine?
    @Environment(\.openCocoaWindow) private var openCocoaWindow

    private var isVMBooted: Bool { library.bootedMachineIdentifiers.contains(vm.id) }

    private var hasOpenSession: Bool { sessionManager.session(for: vm) != nil }

    private var isDuplicating: Bool { library.duplicatingMachineIdentifiers.contains(vm.id) }

    /// Copying a virtual machine that's in use would copy a moving target, so it has to be saved or shut down first.
    private var canDuplicate: Bool { !library.isExecuting(vm) && !isDuplicating }

    private var isHighlighted: Bool { library.recentlyDuplicatedMachineIdentifier == vm.id }

    var body: some View {
        VStack(spacing: 12) {
            ArtworkView(virtualMachine: vm)
                .overlay(alignment: .bottom) {
                    LibraryThumbnailBadges(systemInformation: vm.guestSystemInformation, savedSession: vm.savedSession)
                }
                .overlay {
                    if isDuplicating {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Duplicating…").font(.caption)
                            }
                        }
                    }
                }

            EphemeralTextField($name, alignment: .leading, setFocus: nameFieldFocus) { name in
                Text(name)
            } editableContent: { name in
                TextField("VM Name", text: name)
                    .onSubmit { rename(name.wrappedValue) }
            } validate: { name in
                do {
                    try library.validateNewName(name, for: vm)
                    return true
                } catch {
                    return false
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .disabled(isVMBooted || isDuplicating)
        }
        .padding([.leading, .trailing, .top], 6)
        .padding(.bottom, 12)
        .background(Material.regular, in: backgroundShape)
        .highlightBorder(backgroundShape, color: .accentColor, opacity: isHighlighted ? 0.9 : 0.2)
        .clipShape(backgroundShape)
        .containerShape(backgroundShape)
        .shadow(color: Color.black.opacity(0.14), radius: 12)
        .shadow(color: Color.black.opacity(0.56), radius: 1)
        .scaleEffect(isPressed ? 0.98 : 1)
        .contextMenu { contextMenuItems }
        .sheet(item: $configurationVM) { configurationVM in
            LibraryVMConfigurationSheet(vm: configurationVM)
                .environmentObject(library)
                .environment(library.templatesController)
        }
        .task(id: vm.name) { self.name = vm.name }
        .animation(isPressed ? .linear(duration: 0) : .snappy, value: isPressed)
    }

    private func rename(_ newName: String) {
        guard newName != vm.name else { return }

        do {
            try library.rename(vm, to: name)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            openCocoaWindow(id: "vm-info-\(vm.uuid.uuidString)") {
                VMInfoView(initialMachine: vm).environmentObject(library)
            }
        } label: {
            Label { Text("Get Info…", bundle: #bundle) } icon: { Image(systemName: "info.circle") }
        }


        Button {
            NSWorkspace.shared.selectFile(vm.bundleURL.path, inFileViewerRootedAtPath: vm.bundleURL.deletingLastPathComponent().path)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            configurationVM = vm
        } label: {
            Text("Configure…")
        }
        .disabled(hasOpenSession || isDuplicating)

        Button {
            duplicate()
        } label: {
            Text("Duplicate")
        }
        .disabled(!canDuplicate)
        .help(duplicateHelp)

        Button {
            nameFieldFocus.send(true)
        } label: {
            Text("Rename")
        }
        .disabled(isVMBooted || isDuplicating)

        #if DEBUG
        Button {
            NSWorkspace.shared.open(vm.metadataDirectoryURL)
        } label: {
            Text("Open Data Folder…")
        }
        #endif

        Divider()

        Button {
            library.performMoveToTrash(for: vm)
        } label: {
            Text("Move to Trash")
        }
        .disabled(isVMBooted || isDuplicating)
    }

    private var duplicateHelp: String {
        if library.isExecuting(vm) {
            "Use Save & Close or shut down the virtual machine to duplicate it."
        } else if vm.savedSession != nil {
            "To keep this point for later, duplicate the saved VM before resuming it. Resuming a copy continues that copy."
        } else {
            "Duplicate this virtual machine."
        }
    }

    private func duplicate() {
        Task {
            do {
                try await library.duplicate(vm)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private struct ArtworkView: View {
        var virtualMachine: VBVirtualMachine

        @Environment(\.virtualBuddyShowDesktopPictureThumbnails)
        private var showDesktopPicture

        var body: some View {
            VMArtworkView(virtualMachine: virtualMachine, alwaysUseBlurHash: !showDesktopPicture)
                .id(virtualMachine.blurHashBackgroundContent)
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .aspectRatio(16/9, contentMode: .fit)
                .highlightBorder(.containerRelative)
                .clipShape(.containerRelative)
        }
    }

}

struct HighlightBorderModifier<Shape: InsettableShape>: ViewModifier {
    var shape: Shape
    var color: Color
    var opacity: Double

    func body(content: Content) -> some View {
        ZStack {
            content

            ZStack {
                LinearGradient(colors: [color.opacity(1), color.opacity(0.4)], startPoint: .top, endPoint: .bottom)

                shape
                    .inset(by: 1)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .clipShape(shape)
            .blendMode(.plusLighter)
            .opacity(opacity)
        }
    }
}

extension View {
    func highlightBorder<Shape: InsettableShape>(_ shape: Shape, color: Color = .white, opacity: Double = 0.14) -> some View {
        modifier(HighlightBorderModifier(shape: shape, color: color, opacity: opacity))
    }
}

private struct LibraryThumbnailBadges: View {
    let systemInformation: VBGuestSystemInformation?
    let savedSession: VBSavedSessionDescriptor?

    var body: some View {
        HStack(spacing: 4) {
            if let systemInformation {
                GuestSystemInfoLibraryBadge(report: systemInformation)
            }

            Spacer()

            if let savedSession {
                SavedSessionLibraryBadge(descriptor: savedSession, isCompact: systemInformation != nil)
            }
        }
        .lineLimit(1)
        .padding(3)
        .foregroundStyle(.secondary)
    }
}

private struct GuestSystemInfoLibraryBadge: View {
    let report: VBGuestSystemInformation

    private var version: String {
        guard let version = SoftwareVersion(string: report.information.osVersion) else {
            return report.information.osVersion
        }
        // Keep major.minor even for a .0 release; only omit a zero patch component.
        return version.patch == 0 ? "\(version.major).\(version.minor)" : version.description
    }

    var body: some View {
        Group {
            if let build = report.information.osBuild {
                Text(verbatim: "\(version) (\(build))")
            } else {
                Text(version)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .containerRelative)
        .help(Text("Last reported \(report.receivedAt, format: .dateTime.year().month().day().hour().minute())", bundle: #bundle))
    }
}

/// Marks a saved virtual machine in the library.
private struct SavedSessionLibraryBadge: View {
    let descriptor: VBSavedSessionDescriptor
    let isCompact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: descriptor.isReady ? "tray.and.arrow.down.fill" : "exclamationmark.triangle.fill")

            if isCompact {
                if let date = descriptor.date {
                    Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                }
            } else {
                statusLabel
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .containerRelative)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
        .help(helpText)
    }

    private var helpText: Text {
        let explanation = descriptor.issue?.explanation ?? "This virtual machine is saved. Opening it and pressing Resume continues where you left off."
        if let date = descriptor.date {
            return Text("Saved \(date, format: .dateTime.year().month().day().hour().minute())\n\(explanation)", bundle: #bundle)
        } else {
            return Text(explanation)
        }
    }

    private var statusLabel: Text {
        switch descriptor.status {
        case .ready:
            if let date = descriptor.date {
                Text("Saved \(date, format: .dateTime.month().day().hour().minute())", bundle: #bundle)
            } else {
                Text("Saved", bundle: #bundle)
            }
        case .recoveryRequired:
            Text("Saved – Needs Attention", bundle: #bundle)
        }
    }
}

/// Presents ``VMConfigurationSheet`` for a VM that doesn't have an open session window,
/// saving the configuration directly to the VM's bundle when the user confirms.
private struct LibraryVMConfigurationSheet: View {

    @State private var vm: VBVirtualMachine
    @StateObject private var viewModel: VMConfigurationViewModel

    init(vm: VBVirtualMachine) {
        self._vm = State(initialValue: vm)
        self._viewModel = StateObject(wrappedValue: VMConfigurationViewModel(vm, context: .postInstall))
    }

    var body: some View {
        VMConfigurationSheet(configuration: Binding(
            get: { vm.configuration },
            set: { save($0) }
        ))
        .environmentObject(viewModel)
    }

    private func save(_ configuration: VBMacConfiguration) {
        vm.configuration = configuration

        do {
            try vm.saveMetadata()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

extension VMLibraryController {
    func performMoveToTrash(for vm: VBVirtualMachine) {
        Task {
            do {
                try await moveToTrash(vm)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

#if DEBUG
#Preview("Library") {
    LibraryView()
        .environmentObject(VMLibraryController.preview)
        .environmentObject(VirtualMachineSessionUIManager.shared)
}

#Preview("Thumbnail Badge States") {
    let date = Date(timeIntervalSince1970: 1_793_707_500)
    let saved = VBSavedSessionDescriptor(id: UUID(), date: date, status: .ready)
    let base = VBGuestSystemInformation(receivedAt: date, information: .init(osVersion: "27.0.0", osBuild: "26A123"))
    let minor = VBGuestSystemInformation(receivedAt: date, information: .init(osVersion: "27.2.0", osBuild: "26C123"))
    let patch = VBGuestSystemInformation(receivedAt: date, information: .init(osVersion: "27.0.1", osBuild: "26A456"))
    VStack(alignment: .leading, spacing: 12) {
        LibraryThumbnailBadges(systemInformation: base, savedSession: saved)
        LibraryThumbnailBadges(systemInformation: minor, savedSession: saved)
        LibraryThumbnailBadges(systemInformation: patch, savedSession: saved)
        LibraryThumbnailBadges(systemInformation: patch, savedSession: nil)
        LibraryThumbnailBadges(systemInformation: nil, savedSession: saved)
        LibraryThumbnailBadges(systemInformation: minor, savedSession: .init(id: UUID(), date: date, status: .recoveryRequired(.interruptedAfterResume)))
    }
    .frame(width: 208, alignment: .leading)
    .padding(8)
    .background(.orange.gradient)
}
#endif
