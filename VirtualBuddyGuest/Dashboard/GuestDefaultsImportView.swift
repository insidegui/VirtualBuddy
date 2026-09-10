#if ENABLE_USERDEFAULTS_SYNC
import SwiftUI
import VirtualCore
import VirtualUI
import VirtualWormhole
import Combine

@MainActor
final class DefaultsImportViewModel: ObservableObject {

    let connection: GuestHostSession
    let controller = DefaultsImportController()

    @Published private(set) var domains = [DefaultsDomainDescriptor]()

    init(connection: GuestHostSession) {
        self.connection = connection

        controller.$sortedDomains.assign(to: &$domains)
    }

    func importDomain(with id: DefaultsDomainDescriptor.ID) async throws {
        try await connection.importDomain(with: id)
    }

}

struct GuestDefaultsImportView: View {
    @StateObject private var viewModel: DefaultsImportViewModel

    init(connection: GuestHostSession) {
        _viewModel = StateObject(wrappedValue: DefaultsImportViewModel(connection: connection))
    }

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
        GuestDefaultsImportView(connection: GuestHostSession())
    }
}
#endif

#endif // ENABLE_USERDEFAULTS_SYNC
