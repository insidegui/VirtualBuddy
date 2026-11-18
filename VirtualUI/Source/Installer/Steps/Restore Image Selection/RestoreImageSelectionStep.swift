//
//  RestoreImageSelectionStep.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 20/07/22.
//

import SwiftUI
import SwiftUIIntrospect
import VirtualCore
import Combine

struct RestoreImageSelectionStep: View {
    @StateObject private var controller = RestoreImageSelectionController()
    @EnvironmentObject private var viewModel: VMInstallationViewModel

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.maxContentWidth)
    private var maxContentWidth

    private var topBarHeight: CGFloat { 64 }

    var body: some View {
        HStack(spacing: 0) {
            CatalogGroupPicker(groups: controller.catalog?.groups, selectedGroup: $controller.selectedGroup)

            RestoreImageBrowser(selection: $viewModel.data.resolvedRestoreImage)
        }
        .redacted(reason: controller.isLoading ? .placeholder : [])
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(controller)
        /// `CatalogScrollViewport` eliminates the standard scroll view pocket top bar, which looks
        /// awful with the side-by-side scroll views of the catalog UI, so we do our own scroll edge effect in here.
        .overlay(alignment: .top) {
            if #available(macOS 26, *) {
                ZStack {
                    _VirtualBuddyBarGradient(edge: .top)
                        .blendMode(.destinationOut)

                    _VirtualBuddyVariableBlur(edge: .top)
                }
                .frame(maxWidth: .infinity, minHeight: topBarHeight, maxHeight: topBarHeight)
                .ignoresSafeArea()
            }
        }
        .task(id: viewModel.data.systemType) { loadOptions() }
        .task(id: controller.selectedGroup) {
            if let group = controller.selectedGroup {
                viewModel.data.backgroundHash = BlurHashToken(value: group.darkImage.thumbnail.blurHash)
            } else {
                viewModel.data.backgroundHash = .virtualBuddyBackground
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    loadOptions(skipCache: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Text("Reload"))
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func loadOptions(skipCache: Bool = false) {
        controller.loadRestoreImageOptions(for: viewModel.data.systemType, skipCache: skipCache)
    }

}

struct CatalogScrollViewport: ViewModifier {
    var barHeight: Double = 64

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .introspect(.scrollView, on: .macOS(.v26, .v27)) { scrollView in
                    /// HACK!
                    /// `scrollEdgeEffectHidden` leaves AppKit's scroll pocket backdrop visible over the scrolling content.
                    /// Opt out of the top pocket only, without changing the scroll view's content insets.
                    let key = "allowedPocketEdges"
                    guard scrollView.responds(to: NSSelectorFromString(key)),
                          scrollView.responds(to: NSSelectorFromString("setAllowedPocketEdges:")),
                          let edges = scrollView.value(forKey: key) as? UInt else { return }
                    let top = NSDirectionalRectEdge.top.rawValue
                    if edges & top != 0 {
                        scrollView.setValue(edges & ~top, forKey: key)
                    }
                }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
