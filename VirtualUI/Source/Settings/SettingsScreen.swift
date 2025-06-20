//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore
import DeepLinkSecurity
import BuddyKit

public enum SettingsTab: Int, Identifiable, CaseIterable {
    public var id: RawValue { rawValue }

    case general
    case virtualization
    case automation
}

extension SettingsTab {
    var label: Label<Text, Image> {
        switch self {
        case .general: Label("General", systemImage: "gear")
        case .virtualization: Label("Virtualization", systemImage: "cpu")
        case .automation: Label("Automation", systemImage: "rectangle.grid.1x2")
        }
    }
}

private let kSelectedTabKey = "SettingsScreen.selectedTab"

public struct SettingsScreen: View {

    #if DEBUG
    private let previewTab: SettingsTab?
    #endif

    @EnvironmentObject private var container: VBSettingsContainer
    @Binding private var enableAutomaticUpdates: Bool
    private var deepLinkSentinel: () -> DeepLinkSentinel

    public init(previewTab: SettingsTab? = nil, enableAutomaticUpdates: Binding<Bool>, deepLinkSentinel: @escaping @autoclosure () -> DeepLinkSentinel) {
        self._enableAutomaticUpdates = enableAutomaticUpdates
        self.deepLinkSentinel = deepLinkSentinel

        #if DEBUG
        self.previewTab = previewTab
        #endif
    }

    @State private var alert = AlertContent()

    @AppStorage(kSelectedTabKey)
    private var selectedTab: SettingsTab = .general

    public static var width: CGFloat { 640 }
    public static var minHeight: CGFloat { 420 }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        tab.label
                    }
                }
            }
            .toolbarRemovingSidebarToggle()
            .toolbar {
                // HACK! Don't want sidebar toggle, but want the toolbar visible
                Button("") { }
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView(
                    settings: $container.settings,
                    enableAutomaticUpdates: $enableAutomaticUpdates,
                    alert: $alert
                )
            case .virtualization:
                VirtualizationSettingsView(
                    settings: $container.settings
                )
            case .automation:
                AutomationSettingsView()
                    .environmentObject(deepLinkSentinel())
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: Self.width, maxWidth: Self.width, minHeight: Self.minHeight, maxHeight: .infinity)
        .alert($alert)
        .task {
            #if DEBUG
            guard let previewTab else { return }
            self.selectedTab = previewTab
            #endif
        }
    }
}

// MARK: - Previews

#if DEBUG
private extension VBSettingsContainer {
    static let preview: VBSettingsContainer = {
        VBSettingsContainer(with: UserDefaults())
    }()
}

extension SettingsScreen {
    @ViewBuilder
    static func preview(_ tab: SettingsTab? = nil) -> some View {
        SettingsScreen(previewTab: tab, enableAutomaticUpdates: .constant(true), deepLinkSentinel: .preview)
            .environmentObject(VBSettingsContainer.preview)
    }
}

#Preview("Settings") {
    SettingsScreen.preview()
}
#endif
