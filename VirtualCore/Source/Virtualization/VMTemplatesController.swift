//
//  VMTemplatesController.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 10/6/26.
//

import Foundation
import Combine

@Observable
@MainActor
public final class VMTemplatesController {
    public private(set) var templatesForMacGuest = [VBConfigurationTemplate]()
    public private(set) var templatesForLinuxGuest = [VBConfigurationTemplate]()

    private var cancellables = Set<AnyCancellable>()

    init(library: VMLibraryController) {
        library.$virtualMachines.sink { [weak self] machines in
            self?.loadTemplates(machines)
        }.store(in: &cancellables)
    }

    public func hasTemplates(for guestType: VBGuestType) -> Bool {
        switch guestType {
        case .mac: !templatesForMacGuest.isEmpty
        case .linux: !templatesForLinuxGuest.isEmpty
        }
    }

    public func template(id: VBConfigurationTemplate.ID) -> VBConfigurationTemplate? {
        (templatesForMacGuest + templatesForLinuxGuest).first { $0.id == id }
    }

    private func loadTemplates(_ virtualMachines: [VBVirtualMachine]) {
        /// Create templates for all virtual machines except ones that are not installed yet (such as the one being configured in a pre-install context).
        let templates = virtualMachines
            .filter(\.metadata.installFinished)
            .map { VBConfigurationTemplate(referencing: $0) }

        let forMac = templates.filter { $0.systemType == .mac }
        let forLinux = templates.filter { $0.systemType == .linux }

        if forMac != templatesForMacGuest {
            templatesForMacGuest = forMac
        }
        if forLinux != templatesForLinuxGuest {
            templatesForLinuxGuest = forLinux
        }
    }
}
