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
        self._showTip = .init(wrappedValue: !configuration.sharedFolders.isEmpty)
    }
    
    @State private var isShowingError = false
    @State private var errorMessage = "Error"
    @State private var selection = Set<VBSharedFolder.ID>()
    @State private var selectionBeingRemoved: Set<VBSharedFolder.ID>?
    @State private var isShowingRemovalConfirmation = false
    @State private var isShowingHelpPopover = false
    
    var body: some View {
        GroupedList {
            List(selection: $selection) {
                ForEach($configuration.sharedFolders) { $folder in
                    SharedFolderListItem(folder: $folder)
                        .contextMenu { folderMenu(for: $folder) }
                        .tag(folder.id)
                }
            }
        } headerAccessory: {
            headerAccessory
        } footerAccessory: {
            EmptyView()
        } emptyOverlay: {
            emptyOverlay
        } addButton: { label in
            Button {
                addFolder()
            } label: {
                label
            }
            .help("Add shared folder")
        } removeButton: { label in
            Button {
                confirmRemoval()
            } label: {
                label
            }
            .help("Remove selection from shared folders")
            .disabled(selection.isEmpty)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { note in
            availabilityProvider.refreshAvailabilityIfNeeded(with: note)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { note in
            availabilityProvider.refreshAvailabilityIfNeeded(with: note)
        }
        .onChange(of: configuration) { availabilityProvider.configuration = $0 }
        .onChange(of: configuration.sharedFolders.count) { newValue in
            if newValue > 0 {
                withAnimation(.spring()) {
                    showTip = true
                }
            }
        }
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
    
    @ViewBuilder
    private var emptyOverlay: some View {
        if configuration.sharedFolders.isEmpty {
            Text("This VM has no shared folders.")
            Button("Add Shared Folder") {
                addFolder()
            }
            .buttonStyle(.link)
        }
    }

    @State private var showTip = false
    
    @ViewBuilder
    private var headerAccessory: some View {
        if showTip {
            Button {
                isShowingHelpPopover.toggle()
            } label: {
                Image(systemName: "questionmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .transition(.opacity)
            .popover(isPresented: $isShowingHelpPopover) {
                mountTip
            }
            .help("Shared folders help")
        }
    }
    
    @ViewBuilder
    private var mountTip: some View {
        Text("""
        To make your shared folders available in the virtual machine,
        run the following command in Terminal (Applications > Utilities > Terminal):
        
        ```
        mkdir -p ~/Desktop/VirtualBuddyShared && mount -t virtiofs VirtualBuddyShared ~/Desktop/VirtualBuddyShared
        ```
        
        A folder named "VirtualBuddyShared" will show up on the Desktop.
        """)
        .textSelection(.enabled)
        .foregroundColor(.white)
        .padding()
        .multilineTextAlignment(.leading)
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
