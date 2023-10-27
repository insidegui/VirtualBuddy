////
////  WHDefaultsImportService.swift
////  VirtualWormhole
////
////  Created by Guilherme Rambo on 09/03/23.
////
//
//import Cocoa
//import OSLog
//import Combine
//
//enum DefaultsImportMessage: WHPayload {
//    /// Guest requesting domain export from host.
//    case request(domainID: String)
//    /// Host responding to guest request with domain ID and associated plist.
//    case success(domainID: String, plist: Data)
//    /// Host responding to guest request with domain ID and error message.
//    case failure(domainID: String, error: String)
//
//    static let serviceType = WHDefaultsImportService.self
//}
//
//extension DefaultsImportMessage {
//    var domainID: String {
//        switch self {
//        case .request(let domainID), .success(let domainID, _), .failure(let domainID, _):
//        return domainID
//        }
//    }
//}
//
//public final class WHDefaultsImportService: WormholeService {
//
//    public static let port = WHServicePort.defaultsImport
//
//    public static let id = "defaultsImport"
//
//    private lazy var logger = Logger(for: Self.self)
//
//    var connection: WormholeMultiplexer
//
//    public init(with connection: WormholeMultiplexer) {
//        self.connection = connection
//    }
//
//    public func activate() {
//        logger.debug(#function)
//
//        Task {
//            for try await message in connection.stream(for: DefaultsImportMessage.self) {
//                await handle(message.payload, from: message.senderID)
//            }
//        }
//    }
//
//    private lazy var controller = DefaultsImportController()
//
//    let onDomainResponseReceived = PassthroughSubject<DefaultsImportMessage, Never>()
//
//    func sendExportRequest(for domainID: String) async {
//        assert(connection.side == .guest, "Requesting defaults export is only possible from guest to host")
//
//        await connection.send(DefaultsImportMessage.request(domainID: domainID), to: nil)
//    }
//
//    private func handle(_ message: DefaultsImportMessage, from peerID: WHPeerID) async {
//        logger.debug("Handle message: \(String(describing: message))")
//
//        switch message {
//        case .request(let domainID):
//            await handleDomainRequest(for: domainID, from: peerID)
//        case .success, .failure:
//            await MainActor.run {
//                onDomainResponseReceived.send(message)
//            }
//        }
//    }
//
//    private func handleDomainRequest(for domainID: String, from peerID: WHPeerID) async {
//        do {
//            let data = try await fetchDomainData(for: domainID)
//
//            await connection.send(DefaultsImportMessage.success(domainID: domainID, plist: data), to: peerID)
//        } catch {
//            logger.error("Export failed: \(error, privacy: .public)")
//            
//            await connection.send(DefaultsImportMessage.failure(domainID: domainID, error: error.localizedDescription), to: peerID)
//        }
//    }
//
//    func fetchDescriptor(for domainID: String) throws -> DefaultsDomainDescriptor {
//        guard let domain = controller.descriptors[domainID] else {
//            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Domain \(domainID) not found."])
//        }
//        return domain
//    }
//
//    func temporaryURL(for domainID: String) -> URL {
//        URL(fileURLWithPath: NSTemporaryDirectory())
//            .appendingPathComponent("VirtualBuddyDefaultsExport-\(domainID)-\(Int(Date.now.timeIntervalSinceReferenceDate))")
//            .appendingPathExtension("plist")
//    }
//
//    private func fetchDomainData(for domainID: String) async throws -> Data {
//        let domain = try fetchDescriptor(for: domainID)
//
//        let tempURL = temporaryURL(for: domainID)
//
//        try await domain.exportDefaults(to: tempURL)
//
//        let result = try Data(contentsOf: tempURL)
//
//        try? FileManager.default.removeItem(at: tempURL)
//
//        return result
//    }
//
//}
