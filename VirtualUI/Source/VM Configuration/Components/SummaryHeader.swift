import SwiftUI

struct SummaryHeader<Icon: View, Accessory: View>: View {
    var title: String
    var summary: String?
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, summary: String? = nil, @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.summary = summary
        self.icon = icon
        self.accessory = accessory
    }

    var body: some View {
        HStack {
            HStack {
                icon().frame(width: 22)

                Text(title)
            }
            accessory()

            Spacer()

            if let summary {
                Text(summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
    }
}

extension SummaryHeader where Icon == Image {
    init(_ title: String, image: Image, summary: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.summary = summary
        self.icon = { image }
        self.accessory = accessory
    }

    init(_ title: String, systemImage: String, summary: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(title, image: Image(systemName: systemImage), summary: summary, accessory: accessory)
    }
}

extension SummaryHeader where Icon == Image, Accessory == EmptyView {
    init(_ title: String, image: Image, summary: String? = nil) {
        self.init(title, image: image, summary: summary, accessory: { EmptyView() })
    }

    init(_ title: String, systemImage: String, summary: String? = nil) {
        self.init(title, systemImage: systemImage, summary: summary, accessory: { EmptyView() })
    }
}

extension SummaryHeader where Accessory == EmptyView {
    init(_ title: String, summary: String? = nil, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title, summary: summary, icon: icon, accessory: { EmptyView() })
    }
}
