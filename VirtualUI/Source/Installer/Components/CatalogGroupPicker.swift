import SwiftUI
import VirtualCore
import VirtualCatalog

struct CatalogGroupPicker: View {
    @EnvironmentObject
    private var controller: RestoreImageSelectionController

    var groups: [ResolvedCatalogGroup]
    @Binding var selectedGroup: ResolvedCatalogGroup?

    @State private var scrolledGroupID: ResolvedCatalogGroup.ID?

    var minWidth: CGFloat { 80 }
    var maxWidth: CGFloat { 180 }
    var spacing: CGFloat { containerPadding }

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

    @FocusState
    private var focus: RestoreImageSelectionFocus?

    @ViewBuilder
    private var container: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if #available(macOS 14.0, *) {
                    list
                        .scrollTargetLayout()
                } else {
                    list
                }
            }
            .padding([.top, .leading, .bottom], containerPadding)
        }
        .focusable()
        .focused($focus, equals: RestoreImageSelectionFocus.groups)
        .backported_focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .up:
                if let previous = groups.previous(from: selectedGroup) {
                    selectedGroup = previous
                }
            case .down:
                if let next = groups.next(from: selectedGroup) {
                    selectedGroup = next
                }
            case .right:
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
        .onReceive(controller.$focusedElement) { focus = $0 }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .center, spacing: spacing) {
            ForEach(groups) { group in
                Button {
                    selectedGroup = group
                } label: {
                    CatalogGroupView(group: group)
                }
                .buttonStyle(CatalogGroupButtonStyle(isSelected: group.id == selectedGroup?.id))
                .aspectRatio(320/180, contentMode: .fit)
                .frame(minWidth: minWidth, maxWidth: maxWidth)
            }
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth)
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
