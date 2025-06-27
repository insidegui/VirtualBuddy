import SwiftUI

struct BackportedContentUnavailableView<Actions: View>: View {
    var title: LocalizedStringKey
    var image: Image
    var description: Text?
    @ViewBuilder var actions: () -> Actions

    init(_ title: LocalizedStringKey, image: Image, description: Text? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.image = image
        self.description = description
        self.actions = actions
    }

    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title, image: Image(systemName: systemImage), description: description, actions: actions)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                image
                    .imageScale(.large)
                    .symbolVariant(.fill)

                Text(title)
            }
            .font(.system(.title, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)

            description
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.system(.title3, weight: .regular))

            if Actions.self != EmptyView.self {
                EqualWidthHStack {
                    actions()
                }
                .controlSize(.large)
                .buttonStyle(.backportedContentUnavailableAction)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: 520)
    }
}

extension BackportedContentUnavailableView where Actions == EmptyView {
    init(_ title: LocalizedStringKey, image: Image, description: Text? = nil) {
        self.title = title
        self.image = image
        self.description = description
        self.actions = { EmptyView() }
    }

    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(title, image: Image(systemName: systemImage), description: description)
    }
}

private struct BackportedContentUnavailableActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
                .frame(maxWidth: .infinity)
        }
    }
}

private extension PrimitiveButtonStyle where Self == BackportedContentUnavailableActionButtonStyle {
    static var backportedContentUnavailableAction: BackportedContentUnavailableActionButtonStyle {
        BackportedContentUnavailableActionButtonStyle()
    }
}

#if DEBUG
#Preview {
    BackportedContentUnavailableView(
        "Hello World",
        systemImage: "globe",
        description: Text("""
        Something that should be here is not here.
        
        Because that something that should be here is not here, you're seeing this message.
        """)
    ) {
        Button("Primary Action") {

        }
        .keyboardShortcut(.defaultAction)

        Button("Other Action") {

        }
    }
    .frame(minWidth: 500, minHeight: 300)
    .padding(32)
}
#endif
