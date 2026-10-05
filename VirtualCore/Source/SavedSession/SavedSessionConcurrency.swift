import Foundation

/// Runs file work away from the main actor. Cancelling the caller cancels the work at its next cancellation check.
func performOffMainActor<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    let task = Task.detached(priority: .userInitiated) { try work() }

    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}

/// Serializes operations on a virtual machine. Waiters are served in the order they arrived.
@MainActor
final class VMOperationLease {
    private var isHeld = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    var isBusy: Bool { isHeld }

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }

        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            /// Ownership is handed over directly so that nobody can sneak in between.
            waiters.removeFirst().resume()
        }
    }

    func perform<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}
