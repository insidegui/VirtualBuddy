//
//  LibraryItemView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 21/07/22.
//

import SwiftUI
import VirtualCore

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

    private var isVMBooted: Bool { library.bootedMachineIdentifiers.contains(vm.id) }

    private var hasOpenSession: Bool { sessionManager.session(for: vm) != nil }

    var body: some View {
        VStack(spacing: 12) {
            ArtworkView(virtualMachine: vm)

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
            .disabled(isVMBooted)
        }
        .padding([.leading, .trailing, .top], 8)
        .padding(.bottom, 12)
        .background(Material.regular, in: backgroundShape)
        .highlightBorder(backgroundShape, color: .accentColor, opacity: 0.2)
        .clipShape(backgroundShape)
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
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
        .disabled(hasOpenSession)

        Button {
            duplicate()
        } label: {
            Text("Duplicate")
        }

        Button {
            nameFieldFocus.send(true)
        } label: {
            Text("Rename")
        }
        .disabled(isVMBooted)

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
        .disabled(isVMBooted)
    }

    private func duplicate() {
        Task {
            do {
                try library.duplicate(vm)
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
                .highlightBorder(shape)
                .clipShape(shape)
        }

        private var shape: some InsettableShape {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
#Preview {
    LibraryView()
        .environmentObject(VMLibraryController.preview)
        .environmentObject(VirtualMachineSessionUIManager.shared)
}
#endif
