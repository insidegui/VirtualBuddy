import SwiftUI
import VirtualCore

/// Every alert that's part of saving, resuming and recovering virtual machine sessions.
@MainActor
enum SavedSessionPrompts {

    // MARK: Closing and Quitting

    private static let introductionAcknowledgedKey = "VBSavedSessionIntroductionAcknowledged"

    static var hasAcknowledgedIntroduction: Bool {
        UserDefaults.standard.bool(forKey: introductionAcknowledgedKey)
    }

    /// Explains that closing saves the virtual machine. Only accepting counts as acknowledging it.
    static func confirmIntroduction(quitting: Bool, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close now. Continue later."
        alert.informativeText = """
        Closing a virtual machine saves it exactly as it is, including open apps and unsaved work. \
        The next time you start it, it picks up where you left off.

        You can still use Shut Down to turn off the virtual machine completely instead.
        """
        alert.addButton(withTitle: quitting ? "Save & Quit" : "Save & Close")
        alert.addButton(withTitle: "Cancel")

        guard await alert.present(from: window) == .alertFirstButtonReturn else { return false }

        UserDefaults.standard.set(true, forKey: introductionAcknowledgedKey)

        return true
    }

    /// Saving isn't available: the only way to close is to shut down. A slow shutdown is waited for, never forced.
    static func confirmShutDownInsteadOfSaving(name: String, reason: String, quitting: Bool, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Can’t Save “\(name)”"
        alert.informativeText = """
        \(reason)

        The virtual machine has to be shut down before it can be \(quitting ? "left" : "closed"). VirtualBuddy waits for the guest to shut down.
        """
        alert.addButton(withTitle: quitting ? "Shut Down & Quit" : "Shut Down & Close")
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    static func confirmShutDownInsteadOfSaving(names: [(name: String, reason: String)], from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Can’t Save “\(names[0].name)”" : "Can’t Save \(names.count) Virtual Machines"
        alert.informativeText = names
            .map { "“\($0.name)”: \($0.reason)" }
            .joined(separator: "\n\n")
            + "\n\nThey have to be shut down before VirtualBuddy can quit. VirtualBuddy waits for the guests to shut down."
        alert.addButton(withTitle: "Shut Down & Quit")
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    enum SaveFailureChoice {
        case retry
        case keepOpen
        case shutDown
    }

    static func presentSaveFailure(name: String, error: Error, quitting: Bool, from window: NSWindow?) async -> SaveFailureChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Save “\(name)”"
        alert.informativeText = """
        \(error.localizedDescription)

        \(quitting ? "VirtualBuddy hasn’t quit." : "The virtual machine is still open.")
        """
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Shut Down…")

        switch await alert.present(from: window) {
        case .alertFirstButtonReturn: return .retry
        case .alertThirdButtonReturn: return .shutDown
        default: return .keepOpen
        }
    }

    static func confirmShutDown(name: String, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Shut Down “\(name)”?"
        alert.informativeText = "The guest will be asked to shut down. The virtual machine’s session won’t be saved, so it starts up from scratch next time. VirtualBuddy waits for the guest to finish shutting down."
        alert.addButton(withTitle: "Shut Down")
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    static func confirmForceStop(name: String, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force Stop “\(name)”?"
        alert.informativeText = "The virtual machine is stopped immediately, without letting the guest shut down. Unsaved work is lost, and the guest may need to recover as after an unexpected shutdown."
        alert.addButton(withTitle: "Force Stop").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    // MARK: Resuming

    enum RestoreFailureChoice {
        case retry
        case cancel
        case discardAndStart
    }

    static func presentRestoreFailure(name: String, error: Error, from window: NSWindow?) async -> RestoreFailureChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Resume “\(name)”"
        alert.informativeText = "\(error.localizedDescription)\n\nYour saved session hasn’t been changed."
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Saved Session & Start…").hasDestructiveAction = true

        switch await alert.present(from: window) {
        case .alertFirstButtonReturn: return .retry
        case .alertThirdButtonReturn: return .discardAndStart
        default: return .cancel
        }
    }

    /// The loss that discarding a saved session causes, which must be confirmed every time.
    static let discardExplanation = "This keeps the virtual disks but loses the running session, including unsaved work. The guest may need to recover as after an unexpected shutdown."

    static func confirmDiscard(name: String, startsAfterwards: Bool, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard the Saved Session of “\(name)”?"
        alert.informativeText = discardExplanation
        alert.addButton(withTitle: startsAfterwards ? "Discard & Start" : "Discard").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    static func presentActiveCopyConflict(name: String, conflicts: [SavedSessionActiveCopyConflict], from window: NSWindow?) async -> SavedSessionActiveCopyConflict? {
        let alert = NSAlert()
        alert.messageText = "Can’t Resume “\(name)” Right Now"
        alert.informativeText = conflicts.map(\.explanation).joined(separator: "\n\n")

        let first = conflicts.first
        if let first {
            alert.addButton(withTitle: "Show “\(first.name)”")
        }
        alert.addButton(withTitle: "Cancel")

        guard await alert.present(from: window) == .alertFirstButtonReturn else { return nil }

        return first
    }

    // MARK: Recovery

    enum RecoveryChoice {
        case discard
        case discardAndStart
        case reinstate
        case retryStop
        case showInFinder
        case cancel
    }

    static func presentRecoveryOptions(name: String, issue: SavedSessionIssue, from window: NSWindow?) async -> RecoveryChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(name)” Needs Attention"
        alert.informativeText = issue.explanation

        var choices = [RecoveryChoice]()

        switch issue {
        case .interruptedAfterResume:
            choices = [.discardAndStart, .reinstate, .showInFinder]
        case .stopFailedAfterSave:
            choices = [.retryStop, .discard]
        case .unavailable:
            choices = [.discardAndStart, .showInFinder]
        }

        for choice in choices {
            let button: NSButton
            switch choice {
            case .discardAndStart: button = alert.addButton(withTitle: "Discard Saved Session & Start…")
            case .discard: button = alert.addButton(withTitle: "Discard Saved Session…")
            case .reinstate: button = alert.addButton(withTitle: "Restore Retained Session…")
            case .retryStop: button = alert.addButton(withTitle: "Retry")
            case .showInFinder: button = alert.addButton(withTitle: "Show in Finder")
            case .cancel: continue
            }
            button.hasDestructiveAction = choice == .discardAndStart || choice == .discard
        }
        alert.addButton(withTitle: "Cancel")

        let response = await alert.present(from: window)
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

        return choices.indices.contains(index) ? choices[index] : .cancel
    }

    static func confirmReinstate(name: String, from window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore the Retained Session of “\(name)”?"
        alert.informativeText = "The virtual machine has been running since this session was saved. Restoring the retained session rewinds its disks to that earlier moment, and everything that happened since is lost."
        alert.addButton(withTitle: "Restore & Rewind").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        return await alert.present(from: window) == .alertFirstButtonReturn
    }

    // MARK: Legacy Saved States

    static func presentLegacySavedState(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "Can’t Resume This Saved State"
        alert.informativeText = "This saved state was created by an earlier version of VirtualBuddy, which didn’t keep a copy of the virtual machine’s disks with it. Resuming it could corrupt the virtual machine, so VirtualBuddy won’t. The file hasn’t been changed."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

extension NSAlert {
    /// Presents the alert as a sheet on the window if there is one, or as a modal alert otherwise.
    @MainActor
    func present(from window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.isVisible {
            return await beginSheetModal(for: window)
        } else {
            return runModal()
        }
    }
}
