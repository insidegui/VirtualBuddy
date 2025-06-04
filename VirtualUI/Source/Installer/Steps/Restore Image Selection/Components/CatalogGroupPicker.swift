import SwiftUI
import VirtualCore

struct CatalogGroupPicker: View {
    @EnvironmentObject
    private var controller: RestoreImageSelectionController

    var groups: [ResolvedCatalogGroup]
    @Binding var selectedGroup: ResolvedCatalogGroup?

    @State private var scrolledGroupID: ResolvedCatalogGroup.ID?

    var width: CGFloat { 220 }
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
            LazyVStack(alignment: .center, spacing: spacing) {
                if #available(macOS 14.0, *) {
                    list.scrollTargetLayout()
                } else {
                    list
                }
            }
            .frame(width: width)
            .padding([.top, .leading, .bottom], containerPadding)
            .padding(.trailing, containerPadding * 0.5)
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
}

struct CatalogGroupButtonStyle: ButtonStyle {
    var isSelected: Bool

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .chromeBorder(radius: CatalogGroupView.cornerRadius, highlightEnabled: !isSelected)
            .overlay {
                if isSelected {
                    shape
                        .strokeBorder(Color.white, lineWidth: 2)
                        .blendMode(.plusLighter)
                        .opacity(isFocused ? 0.8 : 0.4)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: CatalogGroupView.cornerRadius, style: .continuous)
    }
}

#if DEBUG
#Preview {
    VMInstallationWizard.preview
}
#endif
