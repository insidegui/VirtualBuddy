import SwiftUI
import Combine
import OSLog

@MainActor
public final class VMSavedStatesController: ObservableObject {

    @Published
    public private(set) var states = [VBSavedStatePackage]()

    private let logger = Logger(for: VMSavedStatesController.self)
    private let filePresenter: DirectoryObserver
    private let updateSignal = PassthroughSubject<URL, Never>()
    private let directoryURL: URL
    private let virtualMachine: VBVirtualMachine

    public init(library: VMLibraryController, virtualMachine: VBVirtualMachine) {
        self.virtualMachine = virtualMachine
        self.directoryURL = library.savedStateDirectoryURL(for: virtualMachine)
        self.filePresenter = DirectoryObserver(
            presentedItemURL: directoryURL,
            fileExtensions: [VBSavedStatePackage.fileExtension],
            label: "SavedStates",
            signal: updateSignal
        )

        loadStates()
        bind()
    }

    private lazy var cancellables = Set<AnyCancellable>()

    private lazy var fileManager = FileManager()

    private func bind() {
        updateSignal
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.loadStates()
            }
            .store(in: &cancellables)
    }

    public func loadStates() {
        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: nil) else {
            logger.error("Failed to open directory at \(self.directoryURL.path, privacy: .public)")
            return
        }

        var loadedStates = [VBSavedStatePackage]()

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == VBSavedStatePackage.fileExtension else { continue }

            do {
                let package = try VBSavedStatePackage(url: url)

                loadedStates.append(package)
            } catch {
                assertionFailure("Failed to construct saved state package: \(error)")
            }
        }

        loadedStates.sort(by: { $0.metadata.date > $1.metadata.date })

        self.states = loadedStates
    }

    public func reload(animated: Bool = true) {
        if animated {
            withAnimation(.spring()) {
                loadStates()
            }
        } else {
            loadStates()
        }
    }

}
