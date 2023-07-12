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

/// A button that's used in ``StatusItemManager`` to provide the contents for the status item
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

    @State private var screen: NSScreen?

    private var height: CGFloat { StatusItemButtonStyle.effectiveHeight(for: screen) }

    var body: some View {
        label()
            .font(.system(size: StatusItemButtonStyle.glyphFontSize))
            .offset(y: StatusItemButtonStyle.glyphOffsetY)
            .frame(minWidth: StatusItemButtonStyle.effectiveWidth, minHeight: height, maxHeight: height)
            .background(background)
            .contentShape(Rectangle())
            .onScreenChanged { screen = $0 }
    }

    @ViewBuilder
    private var background: some View {
        StatusBarHighlightView(isHighlighted: isHighlighted)
            .frame(width: nil)
            .clipShape(RoundedRectangle(cornerRadius: StatusItemButtonStyle.highlightCornerRadius, style: .continuous))
    }

}

struct StatusItemButtonStyle: ButtonStyle {
    static var heightRegular: CGFloat { 22 }
    static var heightTall: CGFloat { 37 }

    static var width: CGFloat { 36 }

    static var verticalPadding: CGFloat { 6 }
    static var horizontalPadding: CGFloat { NSStatusItem.vui_idealPadding }
    static var glyphFontSize: CGFloat { 14 }
    static var glyphOffsetY: CGFloat { 0.5 }

    static var highlightCornerRadius: CGFloat { 4 }

    static func effectiveHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.heightRegular }

        if screen.hasTallMenuBar {
            return Self.heightTall - Self.verticalPadding * 2
        } else {
            return Self.heightRegular
        }
    }

    static var effectiveWidth: CGFloat {
        Self.width - Self.horizontalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        StatusItemButtonLook(label: { configuration.label })
    }

}
