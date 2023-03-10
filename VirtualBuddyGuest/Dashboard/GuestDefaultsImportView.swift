//
//  GuestDefaultsImportView.swift
//  VirtualBuddyGuest
//
//  Created by Guilherme Rambo on 10/03/23.
//

import SwiftUI
import VirtualCore
import VirtualUI
import VirtualWormhole
import Combine

final class DefaultsImportViewModel: ObservableObject {

    let connection: WormholeManager
    let controller = DefaultsImportController()

    @Published private(set) var domains = [DefaultsDomainDescriptor]()

    init(connection: WormholeManager = .sharedGuest) {
        self.connection = connection

        controller.$sortedDomains.assign(to: &$domains)
    }

    private var _client: WHDefaultsImportClient?
    private var client: WHDefaultsImportClient {
        get throws {
            if let _client { return _client }

            let newClient = try connection.makeClient(WHDefaultsImportClient.self)

            _client = newClient

            return newClient
        }
    }

    func importDomain(with id: DefaultsDomainDescriptor.ID) async throws {
        let defaultsClient = try client

        try await defaultsClient.importDomain(with: id)
    }

}

struct GuestDefaultsImportView: View {
    @StateObject var viewModel = DefaultsImportViewModel()

    var body: some View {
        List {
            ForEach(viewModel.domains) { domain in
                DefaultsItemView(domain: domain)
                    .environmentObject(viewModel)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
    }
}

struct DefaultsItemView: View {
    @EnvironmentObject var viewModel: DefaultsImportViewModel

    var domain: DefaultsDomainDescriptor

    var body: some View {
        HStack {
            Image(nsImage: domain.target.iconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 64)
            VStack(alignment: .leading) {
                Text(domain.target.name)
                HStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Import") {
                            importDomain()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    @State private var isLoading = false

    private func importDomain() {
        isLoading = true

        Task {
            do {
                try await viewModel.importDomain(with: domain.id)
            } catch {
                NSAlert(error: error).runModal()
            }

            isLoading = false
        }
    }
}

#if DEBUG
struct GuestDefaultsImportView_Previews: PreviewProvider {
    static var previews: some View {
        GuestDefaultsImportView()
    }
}
#endif
