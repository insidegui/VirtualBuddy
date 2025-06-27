//
//  LibraryView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import VirtualCore

public extension String {
    static let vb_libraryWindowID = "library"
}

public struct LibraryView: View {
    @ObservedObject private var settingsContainer = VBSettingsContainer.current

    @EnvironmentObject private var library: VMLibraryController
    @EnvironmentObject private var sessionManager: VirtualMachineSessionUIManager

    @Environment(\.openCocoaWindow)
    private var openCocoaWindow

    @Environment(\.openVirtualBuddySettings)
    private var openSettings

    public init() { }

    public var body: some View {
        libraryContents
            .frame(minWidth: 600, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .toolbar(content: { toolbarContents })
            .task {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "VBOpenSettings") {
                    openSettings()
                }
                #endif
            }
    }

    private var gridSpacing: CGFloat { 16 }
    private var gridItemMinSize: CGFloat { 240 }
    private var gridColumns: [GridItem] {
        [.init(.adaptive(minimum: gridItemMinSize), spacing: gridSpacing)]
    }
    
    @ViewBuilder
    private var libraryContents: some View {
        switch library.state {
        case .loaded(let vms):
            if vms.isEmpty {
                emptyLibraryView
            } else {
                collectionView(with: vms)
            }
        case .loading:
            ProgressView()
        case .volumeNotMounted:
            libraryError(
                "Library Not Mounted",
                systemImage: "externaldrive.badge.questionmark",
                description: Text("""
                The removable volume that contains your VirtualBuddy library is not mounted.
                
                Your virtual machines will show up here when it's mounted.
                """)
            ) {
                Button("Try Again") {
                    library.loadMachines()
                }
                .keyboardShortcut(.defaultAction)

                Button("Open Settings") {
                    openSettings()
                }
            }
        case .directoryMissing:
            libraryError(
                "Library Missing",
                systemImage: "questionmark.folder",
                description: Text("""
                VirtualBuddy couldn't find your library directory.
                
                Please check your settings. If the library directory exists, this might be a permission issue.
                
                If you have deleted your library directory, you can choose to start a new empty library.
                """)
            ) {
                Button("Open Settings") {
                    openSettings()
                }
                .keyboardShortcut(.defaultAction)

                Button("Create Empty Library") {
                    library.loadMachines(createLibrary: true)
                }
            }
        }
    }

    @ViewBuilder
    private func libraryError<Actions: View>(_ title: LocalizedStringKey, systemImage: String, description: Text, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.large)

                Text(title)
            }
            .font(.system(size: 22, weight: .semibold, design: .rounded))

            description
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                actions()
            }
            .controlSize(.large)
        }
        .textSelection(.enabled)
        .frame(maxWidth: 400)
    }

    @ViewBuilder
    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Text("Your Library is Empty")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("VirtualBuddy is looking for virtual machines in **\(library.libraryURL.collapsedHomePath)**. You can change this in the app's settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Create Your First VM") {
                sessionManager.launchInstallWizard(library: library)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top)
        }
        .frame(maxWidth: 400)
    }

    @ViewBuilder
    private func collectionView(with vms: [VBVirtualMachine]) -> some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(vms) { vm in
                    Button {
                        sessionManager.launch(vm, library: library, options: nil)
                    } label: {
                        LibraryItemView(vm: vm, name: vm.name)
                    }
                    .buttonStyle(.vbLibraryItem)
                    .environmentObject(library)
                }
            }
            .padding()
            .padding(.top)
        }
        .environment(\.virtualBuddyShowDesktopPictureThumbnails, settingsContainer.settings.showDesktopPictureThumbnails)
    }

    @ToolbarContentBuilder
    private var toolbarContents: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                openCocoaWindow {
                    VMInstallationWizard(library: library)
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("New virtual machine")
        }
    }
    
}

fileprivate extension URL {
    var collapsedHomePath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

#if DEBUG
#Preview {
    LibraryView()
        .environmentObject(VMLibraryController.preview)
        .environmentObject(VirtualMachineSessionUIManager.shared)
}
#endif
