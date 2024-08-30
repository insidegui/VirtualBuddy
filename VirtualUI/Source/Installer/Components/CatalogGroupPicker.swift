import SwiftUI
import VirtualCore
import VirtualCatalog

struct CatalogGroupPicker: View {
    @EnvironmentObject
    private var controller: RestoreImageSelectionController

    var groups: [ResolvedCatalogGroup]
    @Binding var selectedGroup: ResolvedCatalogGroup?

    @State private var scrolledGroupID: ResolvedCatalogGroup.ID?

    var minHeight: CGFloat { 80 }
    var maxHeight: CGFloat { 160 }
    var spacing: CGFloat { 16 }

    var body: some View {
        if #available(macOS 14.0, *) {
            container
                .scrollPosition(id: $scrolledGroupID, anchor: .center)
        } else {
            container
        }
    }

    @Environment(\.containerPadding)
    private var containerPadding

    @FocusState private var focused: Bool

    @ViewBuilder
    private var container: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if #available(macOS 14.0, *) {
                    grid
                        .scrollTargetLayout()
                } else {
                    grid
                }
            }
            .padding([.top, .leading, .trailing], containerPadding)
        }
        .focusable()
        .focused($focused)
        .backported_focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if let previous = groups.previous(from: selectedGroup) {
                    selectedGroup = previous
                }
            case .right:
                if let next = groups.next(from: selectedGroup) {
                    selectedGroup = next
                }
            case .down:
                controller.focusedElement = .images
            default:
                break
            }
        }
        .accessibilityRepresentation {
            Picker("Choose option", selection: $selectedGroup) {
                ForEach(groups) { group in
                    Text(group.name)
                        .tag(group)
                }
            }
        }
        .onChange(of: selectedGroup?.id) { groupID in
            withAnimation(.snappy) {
                scrolledGroupID = groupID
            }
        }
        .onReceive(controller.$focusedElement) { element in
            guard element == .groups else { return }
            self.focused = true
        }
    }

    @ViewBuilder
    private var grid: some View {
        LazyHGrid(rows: [.init(.flexible(minimum: minHeight, maximum: maxHeight), spacing: spacing, alignment: .center)], alignment: .center, spacing: spacing) {
            ForEach(groups) { group in
                Button {
                    selectedGroup = group
                } label: {
                    CatalogGroupView(group: group)
                }
                .buttonStyle(CatalogGroupButtonStyle(isSelected: group.id == selectedGroup?.id))
                .aspectRatio(320/180, contentMode: .fit)
            }
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
    }
}

private struct CatalogGroupButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CatalogGroupView.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .opacity(0.7)
                        .blendMode(.plusLighter)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#if DEBUG
@available(macOS 14.0, *)
#Preview {
    @Previewable @State var selectedGroup: ResolvedCatalogGroup? = ResolvedCatalog.previewMac.groups[0]

    CatalogGroupPicker(groups: ResolvedCatalog.previewMac.groups, selectedGroup: $selectedGroup)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 200)
}
#endif
