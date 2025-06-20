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

public enum SettingsTab: Int, Identifiable {
    public var id: RawValue { rawValue }

    case general
    case virtualization
    case automation
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
    private var selectedTab: SettingsTab?

    static var width: CGFloat { 640 }

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: $container.settings, enableAutomaticUpdates: $enableAutomaticUpdates, alert: $alert)
                .tag(SettingsTab.general)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            VirtualizationSettingsView(settings: $container.settings)
                .tag(SettingsTab.virtualization)
                .tabItem {
                    Label("Virtualization", systemImage: "cpu")
                }

            AutomationSettingsView()
                .tag(SettingsTab.automation)
                .environmentObject(deepLinkSentinel())
                .tabItem {
                    Label("Automation", systemImage: "rectangle.grid.1x2")
                }
        }
        .formStyle(.grouped)
        .sidebarAdaptableTabViewStyle()
        .frame(minWidth: Self.width, maxWidth: Self.width, minHeight: 450, maxHeight: .infinity)
        .alert($alert)
        .task {
            #if DEBUG
            guard let previewTab else { return }
            self.selectedTab = previewTab
            #endif
        }
        .toolbarRemovingSidebarToggle()
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
