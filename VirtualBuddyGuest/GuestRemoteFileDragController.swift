import AppKit
import ApplicationServices
import OSLog
import VirtualWormhole

@MainActor
final class GuestRemoteFileDragController: NSObject, NSDraggingSource {
    private final class ActiveDrag {
        let transfer: StagedFileTransfer
        let sourceWindow: RemoteDragSourceWindow
        let sourceView: RemoteDragSourceView
        let eventSource: CGEventSource
        var draggingSession: NSDraggingSession?
        var latestScreenPoint: NSPoint
        var hasPostedMouseDown = false
        var dropRequested = false
        var didReportMovement = false

        init(
            transfer: StagedFileTransfer,
            sourceWindow: RemoteDragSourceWindow,
            sourceView: RemoteDragSourceView,
            eventSource: CGEventSource,
            latestScreenPoint: NSPoint
        ) {
            self.transfer = transfer
            self.sourceWindow = sourceWindow
            self.sourceView = sourceView
            self.eventSource = eventSource
            self.latestScreenPoint = latestScreenPoint
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Guest", category: "RemoteFileDrag")
    private lazy var receiver = GuestFileTransferReceiver { [weak self] transfer in
        self?.didStage(transfer)
    }

    private var messageTask: Task<Void, Never>?
    private var stagedTransfers = [UUID: StagedFileTransfer]()
    private var pendingMessages = [UUID: [FileDragMessage]]()
    private var activeDrag: ActiveDrag?

    func activate() {
        guard messageTask == nil else { return }

        removeAbandonedTransfers()
        receiver.activate()

        messageTask = Task { [weak self] in
            do {
                for try await message in WormholeManager.sharedGuest.stream(for: FileDragMessage.self) {
                    guard message.senderID == .host else { continue }
                    self?.handle(message.payload)
                }
            } catch {
                self?.logger.error("File drag message stream ended: \(error, privacy: .public)")
            }
        }
    }

    func invalidate() {
        receiver.invalidate()
        messageTask?.cancel()
        messageTask = nil
        cancelActiveDrag()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        guard let activeDrag, activeDrag.draggingSession === session else { return }
        report(.sessionWillBegin, for: activeDrag.transfer.sessionID)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let activeDrag,
              activeDrag.draggingSession === session,
              !activeDrag.didReportMovement
        else { return }

        activeDrag.didReportMovement = true
        report(.sessionMoved, for: activeDrag.transfer.sessionID)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard let activeDrag else { return }

        let sessionID = activeDrag.transfer.sessionID
        activeDrag.sourceWindow.orderOut(nil)
        self.activeDrag = nil

        Task {
            await WormholeManager.sharedGuest.send(
                FileDragMessage(
                    action: .result,
                    sessionID: sessionID,
                    operation: operation.rawValue
                ),
                to: nil
            )
        }

        if operation == [] {
            removeTransfer(activeDrag.transfer)
        } else {
            scheduleRemoval(of: activeDrag.transfer)
        }
    }

    private func didStage(_ transfer: StagedFileTransfer) {
        stagedTransfers[transfer.sessionID] = transfer
        report(.staged, for: transfer.sessionID)

        let messages = pendingMessages.removeValue(forKey: transfer.sessionID) ?? []
        for message in messages {
            handle(message)
        }
    }

    private func handle(_ message: FileDragMessage) {
        if message.action == .begin, stagedTransfers[message.sessionID] == nil {
            pendingMessages[message.sessionID, default: []].append(message)
            return
        }

        switch message.action {
        case .begin:
            guard let transfer = stagedTransfers.removeValue(forKey: message.sessionID),
                  let location = message.location
            else { return }
            report(.beginReceived, for: message.sessionID)
            beginDrag(with: transfer, at: screenPoint(for: location))

        case .update:
            guard let activeDrag,
                  activeDrag.transfer.sessionID == message.sessionID,
                  let location = message.location
            else { return }
            let screenPoint = screenPoint(for: location)
            activeDrag.latestScreenPoint = screenPoint

            guard activeDrag.draggingSession != nil else {
                if !activeDrag.hasPostedMouseDown {
                    moveSourceWindow(activeDrag.sourceWindow, to: screenPoint)
                }
                return
            }

            postMouseEvent(.leftMouseDragged, at: screenPoint)

        case .drop:
            guard let activeDrag, activeDrag.transfer.sessionID == message.sessionID else { return }
            let screenPoint = message.location.map(screenPoint(for:)) ?? activeDrag.latestScreenPoint
            activeDrag.latestScreenPoint = screenPoint
            activeDrag.dropRequested = true
            report(.dropReceived, for: message.sessionID)
            if activeDrag.draggingSession != nil {
                postMouseEvent(.leftMouseUp, at: screenPoint)
                report(.mouseUpPosted, for: message.sessionID)
            } else if !activeDrag.hasPostedMouseDown {
                moveSourceWindow(activeDrag.sourceWindow, to: screenPoint)
            }

        case .cancel:
            if let transfer = stagedTransfers.removeValue(forKey: message.sessionID) {
                removeTransfer(transfer)
            }
            pendingMessages[message.sessionID] = nil
            if activeDrag?.transfer.sessionID == message.sessionID {
                cancelActiveDrag()
            }

        case .status, .result:
            break
        }
    }

    private func beginDrag(with transfer: StagedFileTransfer, at screenPoint: NSPoint) {
        cancelActiveDrag()

        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Could not create a Core Graphics event source")
            removeTransfer(transfer)
            return
        }

        let sourceWindow = RemoteDragSourceWindow(
            contentRect: NSRect(x: screenPoint.x - 24, y: screenPoint.y - 24, width: 48, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        sourceWindow.isOpaque = false
        sourceWindow.backgroundColor = .clear
        sourceWindow.hasShadow = false
        sourceWindow.ignoresMouseEvents = false
        sourceWindow.becomesKeyOnlyIfNeeded = true
        sourceWindow.hidesOnDeactivate = false
        sourceWindow.level = .popUpMenu
        sourceWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let sourceView = RemoteDragSourceView(
            frame: sourceWindow.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 48, height: 48)
        )
        sourceWindow.contentView = sourceView
        sourceWindow.orderFrontRegardless()

        let windowPoint = sourceWindow.convertPoint(fromScreen: screenPoint)
        let viewPoint = sourceView.convert(windowPoint, from: nil)

        let draggingItems = transfer.fileURLs.map { fileURL in
            let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            let image = NSWorkspace.shared.icon(forFile: fileURL.path)
            item.setDraggingFrame(
                NSRect(x: viewPoint.x - 16, y: viewPoint.y - 16, width: 32, height: 32),
                contents: image
            )
            return item
        }

        let activeDrag = ActiveDrag(
            transfer: transfer,
            sourceWindow: sourceWindow,
            sourceView: sourceView,
            eventSource: eventSource,
            latestScreenPoint: screenPoint
        )
        self.activeDrag = activeDrag

        sourceView.mouseDownHandler = { [weak self, weak activeDrag] event in
            guard let self,
                  let activeDrag,
                  self.activeDrag === activeDrag
            else { return }

            activeDrag.sourceView.mouseDownHandler = nil

            let session = activeDrag.sourceView.beginDraggingSession(
                with: draggingItems,
                event: event,
                source: self
            )
            session.animatesToStartingPositionsOnCancelOrFail = false
            activeDrag.draggingSession = session

            activeDrag.sourceWindow.ignoresMouseEvents = true
            self.moveOffscreen(activeDrag.sourceWindow)
            self.report(.sessionCreated, for: activeDrag.transfer.sessionID)
            DispatchQueue.main.async { [weak self, weak activeDrag] in
                guard let self,
                      let activeDrag,
                      self.activeDrag === activeDrag
                else { return }

                self.postMouseEvent(.leftMouseDragged, at: activeDrag.latestScreenPoint)

                if activeDrag.dropRequested {
                    self.postMouseEvent(.leftMouseUp, at: activeDrag.latestScreenPoint)
                    self.report(.mouseUpPosted, for: activeDrag.transfer.sessionID)
                }
            }
        }

        report(.sourceReady, for: transfer.sessionID, at: screenPoint)

        guard AXIsProcessTrusted() else {
            report(.inputPermissionMissing, for: transfer.sessionID)
            requestAccessibilityPermission()
            finishDragBeforeSessionStarts(activeDrag)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak activeDrag] in
            guard let self,
                  let activeDrag,
                  self.activeDrag === activeDrag
            else { return }

            let mouseDownPoint = activeDrag.latestScreenPoint
            self.moveSourceWindow(activeDrag.sourceWindow, to: mouseDownPoint)
            activeDrag.sourceWindow.orderFrontRegardless()
            activeDrag.hasPostedMouseDown = true
            self.postMouseEvent(.leftMouseDown, at: mouseDownPoint)
            self.report(.mouseDownPosted, for: activeDrag.transfer.sessionID, at: mouseDownPoint)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak activeDrag] in
                guard let self,
                      let activeDrag,
                      self.activeDrag === activeDrag
                else { return }

                self.report(.pointerObserved, for: activeDrag.transfer.sessionID, at: NSEvent.mouseLocation)
            }

            Task { [weak self, weak activeDrag] in
                try? await Task.sleep(for: .seconds(1))
                guard let self,
                      let activeDrag,
                      self.activeDrag === activeDrag,
                      activeDrag.draggingSession == nil
                else { return }

                self.report(.sessionStartTimedOut, for: activeDrag.transfer.sessionID)
                self.finishDragBeforeSessionStarts(activeDrag)
            }
        }
    }

    private func moveSourceWindow(_ window: NSWindow, to screenPoint: NSPoint) {
        window.setFrameOrigin(
            NSPoint(
                x: screenPoint.x - window.frame.width / 2,
                y: screenPoint.y - window.frame.height / 2
            )
        )
    }

    private func moveOffscreen(_ window: NSWindow) {
        let screenFrame = NSScreen.screens.reduce(NSRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
        let visibleFrame = screenFrame.isNull ? .zero : screenFrame

        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.minX - window.frame.width - 1,
                y: visibleFrame.minY - window.frame.height - 1
            )
        )
    }

    private func cancelActiveDrag() {
        guard let activeDrag else { return }

        if activeDrag.draggingSession != nil {
            postKeyboardEvent(virtualKey: 53, keyDown: true, source: activeDrag.eventSource)
            postKeyboardEvent(virtualKey: 53, keyDown: false, source: activeDrag.eventSource)
        }

        activeDrag.sourceWindow.orderOut(nil)
        removeTransfer(activeDrag.transfer)
        self.activeDrag = nil
    }

    private func postMouseEvent(_ type: CGEventType, at screenPoint: NSPoint) {
        guard let activeDrag,
              let event = CGEvent(
                mouseEventSource: activeDrag.eventSource,
                mouseType: type,
                mouseCursorPosition: quartzPoint(for: screenPoint),
                mouseButton: .left
              )
        else { return }

        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    private func postKeyboardEvent(virtualKey: CGKeyCode, keyDown: Bool, source: CGEventSource) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private func finishDragBeforeSessionStarts(_ activeDrag: ActiveDrag) {
        guard self.activeDrag === activeDrag else { return }

        let sessionID = activeDrag.transfer.sessionID
        activeDrag.sourceWindow.orderOut(nil)
        removeTransfer(activeDrag.transfer)
        self.activeDrag = nil

        Task {
            await WormholeManager.sharedGuest.send(
                FileDragMessage(action: .result, sessionID: sessionID, operation: 0),
                to: nil
            )
        }
    }

    private func report(
        _ status: FileDragMessage.Status,
        for sessionID: UUID,
        at screenPoint: NSPoint? = nil
    ) {
        let location = screenPoint.map(fileDragLocation(for:))
        Task {
            await WormholeManager.sharedGuest.send(
                FileDragMessage(
                    action: .status,
                    sessionID: sessionID,
                    location: location,
                    status: status
                ),
                to: nil
            )
        }
    }

    private func screenPoint(for location: FileDragLocation) -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        return NSPoint(
            x: frame.minX + frame.width * location.x,
            y: frame.minY + frame.height * location.y
        )
    }

    private func quartzPoint(for screenPoint: NSPoint) -> CGPoint {
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(
            x: screenPoint.x,
            y: mainDisplayBounds.maxY - screenPoint.y
        )
    }

    private func fileDragLocation(for screenPoint: NSPoint) -> FileDragLocation {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        guard frame.width > 0, frame.height > 0 else {
            return FileDragLocation(x: 0.5, y: 0.5)
        }

        return FileDragLocation(
            x: (screenPoint.x - frame.minX) / frame.width,
            y: (screenPoint.y - frame.minY) / frame.height
        )
    }

    private func scheduleRemoval(of transfer: StagedFileTransfer) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3_600))
            self?.removeTransfer(transfer)
        }
    }

    private func removeTransfer(_ transfer: StagedFileTransfer) {
        try? FileManager.default.removeItem(at: transfer.directoryURL)
    }

    private func removeAbandonedTransfers() {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "VirtualBuddyFileDrops", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: baseURL)
    }
}

private final class RemoteDragSourceWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RemoteDragSourceView: NSView {
    var mouseDownHandler: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownHandler?(event)
    }
}
