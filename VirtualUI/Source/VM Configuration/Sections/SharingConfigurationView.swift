//
//  SharingConfigurationView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct SharingConfigurationView: View {
    @Binding var configuration: VBMacConfiguration

    @State private var isShowingError = false
    @State private var errorMessage = "Error"
    @State private var selection = Set<VBSharedFolder.ID>()
    @State private var selectionBeingRemoved: Set<VBSharedFolder.ID>?
    @State private var isShowingRemovalConfirmation = false

    init(configuration: Binding<VBMacConfiguration>, selection: Set<VBSharedFolder.ID> = []) {
        self._configuration = configuration
        self._selection = .init(wrappedValue: selection)
    }

    var body: some View {
        clipboardSyncToggle

        sharedFoldersManager
            .alert("Error", isPresented: $isShowingError) {
                Button("OK") { isShowingError = false }
            } message: {
                Text(errorMessage)
            }
    }

    @ViewBuilder
    private var clipboardSyncToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Clipboard Sync", isOn: $configuration.sharedClipboardEnabled)
                .disabled(!VBMacConfiguration.isNativeClipboardSharingSupported)

            Text(VBMacConfiguration.clipboardSharingNotice)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var sharedFoldersManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Folders")

            List(selection: $selection) {
                ForEach($configuration.sharedFolders) { $folder in
                    SharedFolderListItem(folder: $folder)
                        .tag(folder.id)
                        .contextMenu { folderMenu(for: $folder) }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0, content: {
                listButtons
            })
            .materialBackground(.contentBackground, blendMode: .withinWindow, state: .active, in: listShape)
            .controlGroup(cornerRadius: listRadius, level: .secondary)
        }
        .padding(.top)
    }

    private var listRadius: CGFloat { 8 }

    private var listShape: some InsettableShape {
        RoundedRectangle(cornerRadius: listRadius, style: .continuous)
    }

    @ViewBuilder
    private var listButtons: some View {
        HStack {
            Group {
                Button {
                    addFolder()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .help("Add new shared folder")

                removeFoldersButton
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Material.thick, in: Rectangle())
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.black.opacity(0.5))
        }
    }

    @ViewBuilder
    private func folderMenu(for folder: Binding<VBSharedFolder>) -> some View {
        Group {
            Button("Reveal In Finder") {
                NSWorkspace.shared.selectFile(folder.wrappedValue.url.path, inFileViewerRootedAtPath: folder.wrappedValue.url.deletingLastPathComponent().path)
            }

            Divider()

            Button(folder.wrappedValue.isEnabled ? "Disable" : "Enable") {
                folder.wrappedValue.isEnabled.toggle()
            }
        }
        .disabled(!folder.wrappedValue.isAvailable)

        Button("Remove") {
            confirmRemoval(for: [folder.wrappedValue.id])
        }
    }

    private func addFolder() {
        guard let newFolderURL = NSOpenPanel.run(accepting: [.folder]) else {
            return
        }

        do {
            try configuration.addSharedFolder(with: newFolderURL)
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    private func confirmRemoval(for folders: Set<VBSharedFolder.ID>? = nil) {
        let targetFolders = folders ?? selection

        guard !targetFolders.isEmpty else { return }
        selectionBeingRemoved = targetFolders
        isShowingRemovalConfirmation = true
    }

    private func remove(_ identifiers: Set<VBSharedFolder.ID>) {
        configuration.removeSharedFolders(with: identifiers)
    }

    private func removalConfirmationTitle(with selection: Set<VBSharedFolder.ID>) -> String {
        guard selection.count == 1, let singleID = selection.first, let folder = configuration.sharedFolders.first(where: { $0.id == singleID }) else {
            return "Remove \(selection.count) Folders"
        }

        return "Remove \"\(folder.shortNameForDialogs)\""
    }

    private func removalConfirmationMessage(with selection: Set<VBSharedFolder.ID>) -> String {
        guard selection.count == 1, let singleID = selection.first, let folder = configuration.sharedFolders.first(where: { $0.id == singleID }) else {
            return "Are you sure you'd like to remove \(selection.count) shared folders?"
        }

        return "Are you sure you'd like to remove \"\(folder.shortNameForDialogs)\" from the shared folders?"
    }

    @ViewBuilder
    private var removeFoldersButton: some View {
        Button {
            confirmRemoval()
        } label: {
            Image(systemName: "minus")
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .disabled(selection.isEmpty)
        .confirmationDialog("Remove Folders", isPresented: $isShowingRemovalConfirmation, titleVisibility: .visible, presenting: selectionBeingRemoved) { folders in
            Button(role: .cancel) {
                isShowingRemovalConfirmation = false
            } label: {
                Text("Cancel")
            }

            Button(role: .destructive) {
                guard let selectionBeingRemoved else {
                    assertionFailure("How did we get here without a selection?")
                    return
                }

                remove(selectionBeingRemoved)
            } label: {
                Text(removalConfirmationTitle(with: folders))
            }
        } message: { folders in
            Text(removalConfirmationMessage(with: folders))
        }
    }
}

#if DEBUG
struct _ConfigurationSectionPreview<C: View>: View {

    var content: () -> C

    init(@ViewBuilder _ content: @escaping () -> C) {
        self.content = content
    }

    var body: some View {
        ConfigurationSection(collapsed: false, {
            content()
        }, header: {
            Label("SwiftUI Preview", systemImage: "eye")
        })

        .frame(maxWidth: 320, maxHeight: .infinity, alignment: .top)
            .padding()
            .controlGroup()
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct SharingConfigurationView_Previews: PreviewProvider {
    static var config: VBMacConfiguration {
        var c = VBMacConfiguration.default
        c.sharedFolders = [
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99074")!, url: URL(fileURLWithPath: "/Users/insidegui/Desktop"), isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99075")!, url: URL(fileURLWithPath: "/Users/insidegui/Downloads"), isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99076")!, url: URL(fileURLWithPath: "/Volumes/Rambo/Movies"), isEnabled: false, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99077")!, url: URL(fileURLWithPath: "/Some/Invalid/Path"), isEnabled: true, isReadOnly: false),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99078")!, url: URL(fileURLWithPath: "/Users/insidegui/Music"), isEnabled: true, isReadOnly: true),
            .init(id: UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99079")!, url: URL(fileURLWithPath: "/Users/insidegui/Developer"), isEnabled: true, isReadOnly: true),
        ]
        return c
    }

    static var previews: some View {
        _Template(config: config, selection: [UUID(uuidString: "821BA195-D687-4B61-8412-0C6BA6C99074")!])
    }

    struct _Template: View {
        @State var config: VBMacConfiguration
        var selection = Set<VBSharedFolder.ID>()
        init(config: VBMacConfiguration, selection: Set<VBSharedFolder.ID>) {
            self._config = .init(wrappedValue: config)
            self.selection = selection
        }
        var body: some View {
            _ConfigurationSectionPreview {
                SharingConfigurationView(configuration: $config, selection: selection)
            }
        }
    }
}
#endif
