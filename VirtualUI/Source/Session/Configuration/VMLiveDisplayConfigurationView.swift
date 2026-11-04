import SwiftUI
import VirtualCore

struct VMLiveDisplayConfigurationView: View {
    let device: VBDisplayDevice
    let canChangePPI: Bool
    let apply: (VBDisplayDevice) -> Void

    @State private var draft: VBDisplayDevice
    @State private var selectedPreset: VBDisplayPreset?
    @Environment(\.resolvedRestoreImage) private var resolvedRestoreImage

    private var resizeStatus: ResolvedFeatureStatus? {
        resolvedRestoreImage?.feature(id: CatalogFeatureID.displayResize)?.status
    }

    init(device: VBDisplayDevice, canChangePPI: Bool, apply: @escaping (VBDisplayDevice) -> Void) {
        self.device = device
        self.canChangePPI = canChangePPI
        self.apply = apply
        _draft = State(initialValue: device)
    }

    var body: some View {
        ConfigurationSection(collapsingDisabled: true) {
            DisplayConfigurationView(device: $draft, selectedPreset: $selectedPreset, canChangePPI: canChangePPI)

            Text("Apply changes to update the running display. The guest operating system may not support every resolution or pixel density.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if resizeStatus?.isUnsupported == true {
                Text(resizeStatus?.supportMessage ?? "This guest does not support changing its display while running.")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            HStack {
                Spacer()
                Button("Apply Display Settings") { apply(draft) }
                    .disabled(draft == device)
            }
        } header: {
            SummaryHeader(
                "Display",
                systemImage: "display",
                summary: canChangePPI
                    ? "\(device.width)x\(device.height)x\(device.pixelsPerInch)"
                    : "\(device.width)x\(device.height)"
            ) {
                DisplayConfigurationView(device: $draft, selectedPreset: $selectedPreset, canChangePPI: canChangePPI)
                    .presetPicker
                    .frame(width: 24)
            }
        }
        .disabled(resizeStatus?.isUnsupported == true)
        .onChange(of: device) { _, updated in
            draft = updated
            selectedPreset = nil
        }
        .onChange(of: draft) { _, updated in
            guard let preset = selectedPreset else { return }
            if updated.width != preset.device.width || updated.height != preset.device.height
                || updated.pixelsPerInch != preset.device.pixelsPerInch {
                selectedPreset = nil
            }
        }
    }
}

#if DEBUG
#Preview {
    VMLiveDisplayConfigurationView(device: .init(), canChangePPI: true, apply: { _ in })
        .environment(\.vmConfigurationContext, .live)
        .padding()
        .frame(width: 500)
}
#endif
