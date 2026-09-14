import SwiftUI

struct ManagedRestrictionBannerView: View {
    var title: LocalizedStringResource

    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Label(title, systemImage: "lock.shield")
                .font(.headline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .airGlassEffect(.regular.tint(.purple), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .alert("Managed Preferences", isPresented: $isShowingHelp) {
            Button("OK") { isShowingHelp = false }
        } message: {
            Text("A configuration profile applied by your organization is blocking this feature in VirtualBuddy. For more information, please contact your system administrator or IT department.")
        }
    }
}

#if DEBUG
#Preview {
    ManagedRestrictionBannerView(title: "USB passthrough is disabled by your organization.")
        .frame(width: 600, height: 600)
}
#endif
