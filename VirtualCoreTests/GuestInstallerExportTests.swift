import Foundation
import Testing
@testable import VirtualCore

@Suite @MainActor
struct GuestInstallerExportTests {
    @Test func exportSurvivesInitiatingTaskCancellationAndOwnerRelease() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dmg")
        defer { try? FileManager.default.removeItem(at: destination) }
        let started = AsyncStream<Void>.makeStream()
        let finishExport = AsyncStream<Void>.makeStream()
        var exporter: GuestInstallerExport? = GuestInstallerExport()
        weak var retainedExporter = exporter
        var exportTask: Task<Void, Never>?
        var result: Result<URL, Error>?

        // Models a transient view starting the request and then disappearing
        // while the export is suspended doing file work.
        let initiatingTask = Task {
            exportTask = exporter?.start(chooseDestination: { destination }, export: { url in
                started.continuation.yield()
                for await _ in finishExport.stream { break }
                try Task.checkCancellation()
                try Data("installer".utf8).write(to: url)
            }, completion: { result = $0 })
            try? await Task.sleep(for: .seconds(60))
        }
        defer { initiatingTask.cancel(); finishExport.continuation.finish() }
        for await _ in started.stream { break }
        initiatingTask.cancel()
        await initiatingTask.value
        exporter = nil
        #expect(retainedExporter?.phase == .exporting)
        finishExport.continuation.yield()
        finishExport.continuation.finish()
        await exportTask?.value
        #expect(try result?.get() == destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "installer")
    }

    @Test func cancellingSavePanelDoesNotExportOrPresentAnError() async {
        let exporter = GuestInstallerExport()
        let task = exporter.start(chooseDestination: { nil }, export: { _ in
            Issue.record("No destination was accepted")
        }, completion: { _ in
            Issue.record("Dismissing the save panel is not an export failure")
        })
        await task?.value
        #expect(exporter.phase == .idle)
        #expect(!exporter.isBusy)
    }

    @Test func failureRemainsVisibleAndCanBeRetried() async throws {
        let exporter = GuestInstallerExport()
        let destination = URL(fileURLWithPath: "/unused/Guest.dmg")
        let denied = CocoaError(.fileWriteNoPermission)
        var reportedError: Error?
        let failed = exporter.start(chooseDestination: { destination }, export: { _ in
            throw denied
        }, completion: {
            if case .failure(let error) = $0 { reportedError = error }
        })
        await failed?.value
        #expect(exporter.errorMessage == denied.localizedDescription)
        #expect((reportedError as NSError?)?.code == denied.errorCode)
        #expect(!exporter.isBusy)
        let retried = exporter.start(chooseDestination: { destination }, export: { _ in }, completion: { _ in })
        await retried?.value
        #expect(exporter.exportedURL == destination)
        #expect(exporter.errorMessage == nil)
    }

    @Test func unexpectedCancellationIsReportedAsAnInterruption() async {
        let exporter = GuestInstallerExport()
        var reported = false
        let task = exporter.start(chooseDestination: { URL(fileURLWithPath: "/unused/Guest.dmg") }, export: { _ in
            throw CancellationError()
        }, completion: {
            if case .failure = $0 { reported = true }
        })
        await task?.value
        #expect(reported)
        #expect(exporter.errorMessage?.contains("interrupted") == true)
        #expect(!exporter.isBusy)
    }

    @Test func repeatedRequestsDoNotOpenAnotherPanelWhileBusy() async {
        let exporter = GuestInstallerExport()
        let finishChoosing = AsyncStream<Void>.makeStream()
        let first = exporter.start(chooseDestination: {
            for await _ in finishChoosing.stream { break }
            return nil
        }, export: { _ in }, completion: { _ in })
        #expect(exporter.phase == .choosingDestination)
        let second = exporter.start(chooseDestination: {
            Issue.record("Only one destination chooser should be presented")
            return nil
        }, export: { _ in }, completion: { _ in })
        #expect(second == nil)
        finishChoosing.continuation.yield()
        finishChoosing.continuation.finish()
        await first?.value
        #expect(!exporter.isBusy)
    }
}
