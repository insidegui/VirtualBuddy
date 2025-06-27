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

    @AppStorage("hasSeenFirstLaunchExperience")
    private var hasSeenFirstLaunchExperience = false

    private var shouldShowFirstLaunchExperienceOnEmptyLibrary: Bool {
        guard #available(macOS 15.0, *) else { return false }
        return !hasSeenFirstLaunchExperience || UserDefaults.standard.bool(forKey: "VBForceFirstLaunchExperience")
    }

    public init() { }

    public var body: some View {
        libraryContents
            .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
            .toolbar(content: { toolbarContents })
            .task {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "VBOpenSettings") {
                    openSettings()
                }
                #endif
            }
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

    private var gridSpacing: CGFloat { 16 }
    private var gridItemMinSize: CGFloat { 240 }
    private var gridColumns: [GridItem] {
        [.init(.adaptive(minimum: gridItemMinSize), spacing: gridSpacing)]
    }
    
    @ViewBuilder
    private var libraryContents: some View {
        ZStack {
            BlurHashFullBleedBackground(content: .blurHash(.virtualBuddyBackground))
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .fullBleedBackgroundDimmed(![.loaded, .loading].contains(library.state.id))

            Group {
                switch library.state {
                case .loaded(let machines):
                    grid(machines)
                case .empty:
                    if shouldShowFirstLaunchExperienceOnEmptyLibrary {
                        FirstLaunchExperienceView {
                            sessionManager.launchInstallWizard(library: library)
                        }
                        .task { hasSeenFirstLaunchExperience = true }
                    } else {
                        libraryEmptyMessage
                    }
                case .loading:
                    EmptyView()
                case .volumeNotMounted:
                    libraryVolumeNotMountedMessage
                case .directoryMissing:
                    libraryDirectoryMissingMessage
                }
            }
            .transition(.scale(scale: 1.5).combined(with: .opacity))
        }
        .animation(.snappy, value: library.state.id)
    }

    @ViewBuilder
    private func grid(_ machines: [VBVirtualMachine]) -> some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(machines) { vm in
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

    @ViewBuilder
    private var libraryVolumeNotMountedMessage: some View {
        BackportedContentUnavailableView(
            "Library Not Mounted",
            systemImage: "externaldrive.badge.questionmark",
            description: Text("""
            The volume containing your VirtualBuddy library is not currently mounted.
            Once mounted, your virtual machines will appear here.
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
    }

    @ViewBuilder
    private var libraryDirectoryMissingMessage: some View {
        BackportedContentUnavailableView(
            "Library Missing",
            systemImage: "questionmark.folder",
            description: Text("""
            VirtualBuddy is unable to locate your library directory.

            Review your settings to ensure the directory is set correctly. If it exists, there may be a permission problem.

            If you’ve deleted the library directory, you can start a new empty library.
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

    @ViewBuilder
    private var libraryEmptyMessage: some View {
        BackportedContentUnavailableView(
            "No Virtual Machines",
            systemImage: "square.grid.2x2",
            description: Text("""
            You haven’t created any virtual machines yet. You can create a new one, or select a different library directory in settings.
            """)
        ) {
            Button("Create Virtual Machine") {
                sessionManager.launchInstallWizard(library: library)
            }
            .keyboardShortcut(.defaultAction)

            Button("Open Settings") {
                openSettings()
            }
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
