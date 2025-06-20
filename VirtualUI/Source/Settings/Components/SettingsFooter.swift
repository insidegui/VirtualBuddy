import SwiftUI
import BuddyKit

struct SettingsFooter: View {
    var summaryText: () -> Text
    var helpText: (() -> Text)? = nil

    @State private var helpExpanded = false

    var body: some View {
        VStack(alignment: .listRowSeparatorLeading, spacing: 8) {
            HStack(spacing: 0) {
                summaryText()

                Spacer()

                if helpText != nil {
                    Group {
                        if #available(macOS 14.0, *) {
                            HelpLink {
                                helpExpanded.toggle()
                            }
                        } else {
                            Button {
                                helpExpanded.toggle()
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                        }
                    }
                    .controlSize(.small)
                }
            }

            if let helpText, helpExpanded {
                helpText()
            }
        }
        .settingsFooterStyle()
    }
}

extension View {
    @ViewBuilder
    func settingsFooterStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .padding(.leading, 8)
            .textSelection(.enabled)
    }
}
