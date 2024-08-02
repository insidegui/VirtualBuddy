import SwiftUI
import VirtualCore
import VirtualCatalog

struct CatalogGroupPicker: View {
    var groups: [ResolvedCatalogGroup]
    @Binding var selectedGroup: ResolvedCatalogGroup?

    @State private var scrolledGroupID: ResolvedCatalogGroup.ID?

    var minHeight: CGFloat { 80 }
    var maxHeight: CGFloat { 300 }
    var spacing: CGFloat { 16 }

    var body: some View {
        if #available(macOS 14.0, *) {
            container
                .scrollPosition(id: $scrolledGroupID, anchor: .center)
        } else {
            container
        }
    }

    @ViewBuilder
    private var container: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(macOS 14.0, *) {
                grid
                    .scrollTargetLayout()
            } else {
                grid
            }
        }
        .keyboardNavigation { direction in
            switch direction {
            case .left:
                if let previous = groups.previous(from: selectedGroup) {
                    selectedGroup = previous
                    scrolledGroupID = previous.id
                }
            case .right:
                if let next = groups.next(from: selectedGroup) {
                    selectedGroup = next
                    scrolledGroupID = next.id
                }
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
