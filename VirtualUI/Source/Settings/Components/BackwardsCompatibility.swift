import SwiftUI

extension View {
    @ViewBuilder
    func toolbarRemovingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

    @ViewBuilder
    func sidebarAdaptableTabViewStyle() -> some View {
        if #available(macOS 15.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
