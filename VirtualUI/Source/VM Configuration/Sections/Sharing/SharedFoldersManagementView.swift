//
//  SharedFoldersManagementView.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI
import VirtualCore

struct SharedFoldersManagementView: View {
    
    @Binding var configuration: VBMacConfiguration
    
    @StateObject private var availabilityProvider: SharedFoldersAvailabilityProvider
    
    init(configuration: Binding<VBMacConfiguration>) {
        self._configuration = configuration
        self._availabilityProvider = .init(wrappedValue: SharedFoldersAvailabilityProvider(configuration.wrappedValue))
    }
    
    @State private var isShowingError = false
    @State private var errorMessage = "Error"
    @State private var selection = Set<VBSharedFolder.ID>()
    @State private var selectionBeingRemoved: Set<VBSharedFolder.ID>?
    @State private var isShowingRemovalConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Folders")

            List(selection: $selection) {
                ForEach($configuration.sharedFolders) { $folder in
                    SharedFolderListItem(folder: $folder)
                        .contextMenu { folderMenu(for: $folder) }
                        .tag(folder.id)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 140)
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0, content: {
                listButtons
            })
            .materialBackground(.contentBackground, blendMode: .withinWindow, state: .active, in: listShape)
            .controlGroup(cornerRadius: listRadius, level: .secondary)
        }
        .padding(.top)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { note in
            availabilityProvider.refreshAvailabilityIfNeeded(with: note)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { note in
            availabilityProvider.refreshAvailabilityIfNeeded(with: note)
        }
        .onChange(of: configuration) { availabilityProvider.configuration = $0 }
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
            Toggle("Enabled", isOn: folder.isEnabled)
            
            Toggle("Read Only", isOn: folder.isReadOnly)

            Divider()

            Button("Reveal In Finder") {
                NSWorkspace.shared.selectFile(folder.wrappedValue.url.path, inFileViewerRootedAtPath: folder.wrappedValue.url.deletingLastPathComponent().path)
            }
        }
        .disabled(!availabilityProvider.isFolderAvailable(folder.wrappedValue))

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

private final class SharedFoldersAvailabilityProvider: ObservableObject {
    
    var configuration: VBMacConfiguration
    
    init(_ configuration: VBMacConfiguration) {
        self.configuration = configuration
        refreshAvailability()
    }
    
    @Published private(set) var folderAvailability: [VBSharedFolder.ID: Bool] = [:]
    
    func isFolderAvailable(_ folder: VBSharedFolder) -> Bool {
        folderAvailability[folder.id] ?? false
    }
    
    func refreshAvailability() {
        for folder in configuration.sharedFolders {
            folderAvailability[folder.id] = folder.isAvailable
        }
    }
    
    func refreshAvailabilityIfNeeded(with notification: Notification) {
        guard let volumeURL = notification.userInfo?["NSWorkspaceVolumeURLKey"] as? URL else { return }
        guard configuration.hasSharedFolders(inVolume: volumeURL) else { return }
        
        refreshAvailability()
    }
    
}

#if DEBUG
struct SharedFoldersManagementView_Previews: PreviewProvider {
    static var previews: some View {
        SharingConfigurationView_Previews.previews
    }
}
#endif
