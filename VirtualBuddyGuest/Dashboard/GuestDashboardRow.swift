import SwiftUI
import VirtualUI

enum GuestDashboardMetrics {
    static let width: CGFloat = 300
    /// Distance between the panel's edges and the highlight of its rows.
    static let rowInset: CGFloat = 6
    static let rowPadding = EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 10)
    /// Aligns standalone content with the content of the rows.
    static let contentInset: CGFloat = rowInset + rowPadding.leading
    static let iconSize: CGFloat = 28

    /// Keeps row highlights concentric with the panel.
    static var rowCornerRadius: CGFloat {
        max(StatusBarMenuChromeMetrics.cornerRadius - rowInset, 6)
    }
}

/// The label for a dashboard row that performs an action, with an icon, a title and an optional subtitle.
struct GuestDashboardRowLabel<Accessory: View>: View {
    var title: LocalizedStringKey
    var subtitle: Text?
    var systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: GuestDashboardMetrics.iconSize, height: GuestDashboardMetrics.iconSize)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)

                subtitle?
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

extension GuestDashboardRowLabel where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: Text? = nil, systemImage: String) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

/// Gives buttons in the dashboard the look of a menu item, with a highlight that follows the pointer.
struct GuestDashboardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration

        @Environment(\.isEnabled)
        private var isEnabled

        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(GuestDashboardMetrics.rowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: GuestDashboardMetrics.rowCornerRadius, style: .continuous)
                        .fill(.primary.opacity(backgroundOpacity))
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovered = $0 }
        }

        private var backgroundOpacity: Double {
            guard isEnabled else { return 0 }

            return if configuration.isPressed {
                0.16
            } else if isHovered {
                0.1
            } else {
                0
            }
        }
    }
}

extension ButtonStyle where Self == GuestDashboardRowButtonStyle {
    static var guestDashboardRow: GuestDashboardRowButtonStyle { GuestDashboardRowButtonStyle() }
}
