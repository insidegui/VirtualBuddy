//
//  RestoreImageBrowser.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 02/08/24.
//

import SwiftUI
import VirtualCore
import Combine
import BuddyKit

struct ChannelGroup: Identifiable, Hashable {
    var id: CatalogChannel.ID { channel.id }
    var channel: CatalogChannel
    var images: [ResolvedRestoreImage]
}

struct RestoreImageBrowser: View {
    @EnvironmentObject
    private var controller: RestoreImageSelectionController

    @Binding var selection: ResolvedRestoreImage?

    init(selection: Binding<ResolvedRestoreImage?>) {
        self._selection = selection
    }

    @Environment(\.containerPadding)
    private var containerPadding

    @Environment(\.maxContentWidth)
    private var maxContentWidth

    @FocusState
    private var focus: RestoreImageSelectionFocus?

    @State private var scrolledImageID: ResolvedRestoreImage.ID?

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                scrollView
                    .scrollPosition(id: $scrolledImageID, anchor: .center)
            } else {
                scrollView
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: containerPadding) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: containerPadding) }
        .focusable()
        .focused($focus, equals: RestoreImageSelectionFocus.images)
        .backported_focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .down:
                if let previous = controller.images.next(from: controller.selectedRestoreImage) {
                    controller.selectedRestoreImage = previous
                }
            case .up:
                if let next = controller.images.previous(from: controller.selectedRestoreImage) {
                    controller.selectedRestoreImage = next
                }
            case .left:
                controller.focusedElement = .groups
            default:
                break
            }
        }
        .onChange(of: selection) { image in
            guard let image else { return }

            scrolledImageID = image.id

            guard image.id != controller.selectedRestoreImage?.id else { return }

            controller.selectedRestoreImage = image
        }
        .onReceive(controller.$focusedElement) { focus = $0 }
        .onReceive(controller.$selectedRestoreImage.removeDuplicates()) {
            guard let newSelection = $0 else { return }
            guard newSelection.id != selection?.id else { return }
            guard newSelection.image.group == controller.selectedGroup?.id else { return }

            selection = $0
        }
    }

    @Environment(\.redactionReasons)
    private var redaction

    @ViewBuilder
    private var scrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if #available(macOS 14.0, *) {
                stack.scrollTargetLayout()
            } else {
                stack
            }
        }
    }

    @ViewBuilder
    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
            if redaction.isEmpty {
                ForEach(controller.channelGroups) { group in
                    section(for: group)
                }
            } else if controller.isLoading {
                /// Placeholders are only displayed when controller is loading to avoid jumps when loading happens quickly (or not at all).
                ForEach(0...12, id: \.self) { _ in
                    RestoreImageButton(image: .placeholder, isSelected: false, action: { })
                }
            }
        }
        .padding(.trailing, containerPadding)
        .padding(.leading, containerPadding * 0.5)
    }

    @ViewBuilder
    private func section(for group: ChannelGroup) -> some View {
        Section {
            ForEach(group.images) { image in
                RestoreImageButton(image: image, isSelected: image.id == selection?.id) {
                    selection = image
                }
                .tag(image)
            }
        }
    }
}

private struct RestoreImageButton: View {
    var image: ResolvedRestoreImage
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            label
        }
        .buttonStyle(RestoreImageButtonStyle(isSelected: isSelected))
    }

    @ViewBuilder
    var label: some View {
        HStack {
            downloadState

            Spacer()

            details

            supportState
        }
        .monospacedDigit()
        .contextMenu {
            Button("Copy Download Link") {
                Pasteboard.general.string = image.url.absoluteString
            }

            Button("Copy Build Number") {
                Pasteboard.general.string = image.build
            }
        }
    }

    @ViewBuilder
    private var downloadState: some View {
        HStack {
            Image(systemName: image.isDownloaded ? "internaldrive" : "arrow.down.circle")
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .help(image.isDownloaded ? "This version is available from your previous downloads." : "This version needs to be downloaded.")

            Text(image.name)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .help(image.name)
        }
        .font(.headline)
    }

    @ViewBuilder
    private var details: some View {
        HStack(spacing: 4) {
            Text(image.build)

            Text("·")

            Text(image.formattedDownloadSize)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    private var supportState: some View {
        RestoreImageFeatureStatusButton(image: image)
    }
}

struct RestoreImageFeatureStatusButton: View {
    let image: ResolvedRestoreImage

    var status: ResolvedFeatureStatus { image.status }

    var helpText: String {
        switch status {
        case .supported: "This version is supported on your Mac. Click for details about supported features."
        case .warning(let message): message
        case .unsupported(let message): message
        }
    }

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail.toggle()
        } label: {
            FeatureStatusLabel(status: status)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .popover(isPresented: $showingDetail) {
            RestoreImageFeatureDetailView(image: image)
        }
    }
}

struct FeatureStatusLabel: View {
    var status: ResolvedFeatureStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .foregroundStyle(status.color)
            .symbolVariant(.circle.fill)
    }
}

struct RestoreImageFeatureDetailView: View {
    static var padding: Double { 12 }

    let image: ResolvedRestoreImage

    var body: some View {
        VStack(spacing: 16) {
            topLevelStatus

            VStack(alignment: .leading, spacing: 8) {
                ForEach(image.features) { feature in
                    RestoreImageFeatureDetailItem(feature: feature)
                }
            }
        }
        .frame(width: 340, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var topLevelStatus: some View {
        switch image.status {
        case .supported:
            EmptyView()
        case .warning(let message), .unsupported(let message):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FeatureStatusLabel(status: image.status)

                    Text("This Version May Not Work")
                }
                    .imageScale(.large)
                    .font(.headline)

                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background {
                image.status.color
                    .blendMode(.plusDarker)
                    .opacity(0.2)
            }
            .controlGroup()
            .textSelection(.enabled)
        }
    }
}

struct RestoreImageFeatureDetailItem: View {
    let feature: ResolvedVirtualizationFeature

    var status: ResolvedFeatureStatus { feature.status }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    FeatureStatusLabel(status: status)

                    Text(feature.name)

                    Spacer()

                }
                .font(.headline)

                Text(feature.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .padding(RestoreImageFeatureDetailView.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlGroup(level: .secondary)
    }
}

extension ResolvedFeatureStatus {
    var topLevelTitle: String {
        switch self {
        case .supported: "This Version Should Work"
        case .warning: "This Version May Not Work"
        case .unsupported: "This Version Will Not Work"
        }
    }

    var systemImage: String {
        switch self {
        case .supported: "checkmark"
        case .warning: "exclamationmark.triangle"
        case .unsupported: "xmark"
        }
    }

    var color: Color {
        switch self {
        case .supported: .green
        case .warning: .yellow
        case .unsupported: .red
        }
    }

    var textColor: Color {
        switch self {
        case .supported: .green
        case .warning, .unsupported: .yellow
        }
    }

    var subtitle: String {
        switch self {
        case .supported: "Supported"
        case .warning: "Warning"
        case .unsupported: "Not Supported"
        }
    }
}

struct RestoreImageButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = 14

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.thin, in: shape)
            .background(Color.black.opacity(0.14).blendMode(.plusDarker), in: shape)
            .chromeBorder(radius: cornerRadius, highlightEnabled: !isSelected, shadowEnabled: false, highlightIntensity: 0.4)
            .overlay {
                if isSelected {
                    shape
                        .strokeBorder(Color.white, lineWidth: 2)
                        .blendMode(.plusLighter)
                        .opacity(isFocused ? 0.8 : 0.4)
                }
            }
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension ResolvedRestoreImage {
    var formattedDownloadSize: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
    }
}

#if DEBUG
@available(macOS 14.0, *)
#Preview {
    VMInstallationWizard.preview
}

#Preview("Feature Detail") {
    RestoreImageFeatureDetailView(image: .previewMac)
}
#endif
