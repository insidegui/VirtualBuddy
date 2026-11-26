//
//  PreferencesView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 05/06/22.
//

import SwiftUI
import VirtualCore
import DeepLinkSecurity

public enum SettingsTab: Int, Identifiable, CaseIterable {
    public var id: RawValue { rawValue }

    case general
    case virtualization
    case security
    case developer
}

extension SettingsTab {
    var label: Label<Text, Image> {
        switch self {
        case .general: Label("General", systemImage: "gear")
        case .virtualization: Label("Virtualization", systemImage: "cpu")
        case .security: Label("Security", systemImage: "lock")
        case .developer: Label("Developer", systemImage: "hammer")
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
    private let deepLinkSentinel: () -> DeepLinkSentinel
    private let securitySession: SecuritySettingsSession

    public init(
        previewTab: SettingsTab? = nil,
        enableAutomaticUpdates: Binding<Bool>,
        deepLinkSentinel: @escaping @autoclosure () -> DeepLinkSentinel,
        securitySession: SecuritySettingsSession = .shared
    ) {
        self._enableAutomaticUpdates = enableAutomaticUpdates
        self.deepLinkSentinel = deepLinkSentinel
        self.securitySession = securitySession

        #if DEBUG
        self.previewTab = previewTab
        #endif
    }

    @AppStorage(kSelectedTabKey)
    private var selectedTab: SettingsTab = .general

    public var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { tab.label }
                    .tag(tab)
            }
        }
        .navigationTitle(Text("Settings", bundle: #bundle))
        .locksSecuritySettingsWhenUnattended(securitySession)
        .task {
            #if DEBUG
            guard let previewTab else { return }
            self.selectedTab = previewTab
            #endif
        }
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(settings: $container.settings, enableAutomaticUpdates: $enableAutomaticUpdates)
        case .virtualization:
            VirtualizationSettingsView(settings: $container.settings)
        case .security:
            SecuritySettingsView(session: securitySession)
                .environmentObject(deepLinkSentinel())
        case .developer:
            DeveloperSettingsView(isEnabled: $container.settings.developerFeaturesEnabled)
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
    static func preview(_ tab: SettingsTab? = nil, securitySession: SecuritySettingsSession? = nil) -> some View {
        SettingsScreen(previewTab: tab, enableAutomaticUpdates: .constant(true), deepLinkSentinel: .preview, securitySession: securitySession ?? .preview())
            .environmentObject(VBSettingsContainer.preview)
    }
}

#Preview("Settings") {
    SettingsScreen.preview()
}
#endif
