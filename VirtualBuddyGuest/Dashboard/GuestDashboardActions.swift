import SwiftUI

/// Actions the dashboard can perform that affect the app outside of the menu bar panel.
struct GuestDashboardActions {
    /// Shows one of the app's dedicated windows.
    var showWindow: @MainActor (GuestWindow) -> Void = { _ in }
    /// Dismisses the menu bar panel.
    var dismiss: @MainActor () -> Void = { }
}

extension EnvironmentValues {
    @Entry var guestDashboardActions = GuestDashboardActions()
}
