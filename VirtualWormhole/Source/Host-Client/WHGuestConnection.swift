import Foundation

protocol WHGuestConnection: AnyObject {
    func connect(using fileDescriptor: Int32, invalidationHandler: @escaping (Self) -> Void) async throws
}
