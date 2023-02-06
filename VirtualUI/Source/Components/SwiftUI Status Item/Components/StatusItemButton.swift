import Cocoa
import SwiftUI

private struct StatusItemHighlightedEnvironmentKey: EnvironmentKey {
    static var defaultValue = false
}

extension EnvironmentValues {

    /// Whether the status item should be drawn highlighted.
    fileprivate(set) var isStatusItemHighlighted: Bool {
        get { self[StatusItemHighlightedEnvironmentKey.self] }
        set { self[StatusItemHighlightedEnvironmentKey.self] = newValue }
    }

}

/// A button that's used in ``ModernBatteryStatusView`` to provide the contents for the status item
/// when using the `.button` content type.
/// Custom views can use ``StatusItemButtonLook`` to implement a view that's compatible
/// with status items, but that aren't necessarily a button.
struct StatusItemButton<Label: View, Provider: StatusItemProvider>: View {

    @EnvironmentObject private var provider: Provider

    var label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }
    
    var body: some View {
        Button {
            provider.togglePanelVisible()
        } label: {
            label()
        }
        .buttonStyle(StatusItemButtonStyle())
        .statusItemHighlightedEnvironment(from: provider)
    }

}

extension View {
    /// Reads properties from the specified provider and sets the `isStatusItemHighlighted` environment value accordingly.
    /// Apply at the root of hierarchies that expect to be able to read the `isStatusItemHighlighted` value.
    ///
    /// This is handy because the `isStatusItemHighlighted` property from `StatusItemManager` is not always
    /// enough to determine whether to draw the highlight, which also depends on status item occlusion state.
    func statusItemHighlightedEnvironment<Provider>(from provider: Provider) -> some View where Provider: StatusItemProvider {
        environment(\.isStatusItemHighlighted,
                     provider.isStatusItemHighlighted && !provider.isStatusItemOccluded)
    }
}

/// A view that looks like ``StatusItemButton``, but can be used as a wrapper
/// for completely custom status items that do not use the button view.
struct StatusItemButtonLook<Label: View>: View {

    var label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    @Environment(\.isStatusItemHighlighted)
    private var isHighlighted

    var body: some View {
        label()
            .font(.system(size: StatusItemButtonStyle.glyphFontSize))
            .offset(y: StatusItemButtonStyle.glyphOffsetY)
            .frame(width: nil, height: StatusItemButtonStyle.effectiveHeight)
            .background(background)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var background: some View {
        StatusBarHighlightView(isHighlighted: isHighlighted)
            .frame(width: nil)
            .clipShape(RoundedRectangle(cornerRadius: StatusItemButtonStyle.highlightCornerRadius, style: .continuous))
    }

}

struct StatusItemButtonStyle: ButtonStyle {
    static var height: CGFloat { 37 }
    static var width: CGFloat { 40 }

    static var verticalPadding: CGFloat { 6 }
    static var horizontalPadding: CGFloat { NSStatusItem.vui_idealPadding }
    static var glyphFontSize: CGFloat { 14 }
    static var glyphOffsetY: CGFloat { 0.5 }

    static var highlightCornerRadius: CGFloat { 4 }

    static var effectiveHeight: CGFloat {
        Self.height - Self.verticalPadding * 2
    }

    static var effectiveWidth: CGFloat {
        Self.width - Self.horizontalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        StatusItemButtonLook(label: { configuration.label })
    }

}

#if DEBUG
@available(macOS 12.0, *)
struct StatusItemButton_Previews: PreviewProvider {
    static var previews: some View {
        Preview(highlighted: false, thiccBoi: true)
            .previewDisplayName("Notch")
        Preview(highlighted: true, thiccBoi: true)
            .previewDisplayName("Notch - Highlighted")

        Preview(highlighted: false, thiccBoi: false)
            .previewDisplayName("Regular")
        Preview(highlighted: true, thiccBoi: false)
            .previewDisplayName("Regular - Highlighted")
    }

    private final class FakeStatusItemProvider: StatusItemProvider {
        @Published var isStatusItemHighlighted: Bool
        @Published var isStatusItemOccluded: Bool

        func showPopUpMenu(using builder: () -> NSMenu) {
            
        }

        func togglePanelVisible() {
            
        }

        init(_ value: Bool) {
            self.isStatusItemHighlighted = value
            self.isStatusItemOccluded = false
        }
    }

    private struct Preview: View {
        var highlighted: Bool
        var thiccBoi: Bool

        var fakeMenuBarHeight: CGFloat {
            if thiccBoi {
                return 37
            } else {
                return 22
            }
        }

        var body: some View {
            ZStack {
                Rectangle()
                    .frame(width: 200, height: fakeMenuBarHeight)
                    .foregroundStyle(Material.thin)

                StatusItemButtonLook {
                    Image(systemName: "switch.2")
                }
                .environmentObject(FakeStatusItemProvider(highlighted))
            }
            .frame(height: fakeMenuBarHeight)
        }
    }
}
#endif
