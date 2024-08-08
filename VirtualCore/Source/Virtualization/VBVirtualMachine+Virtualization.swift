//
//  VBVirtualMachine+Virtualization.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 21/07/22.
//

import Foundation
import Virtualization

extension VBVirtualMachine {

    func fetchOrGenerateAuxiliaryStorage(hardwareModel: VZMacHardwareModel? = nil) throws -> VZMacAuxiliaryStorage {
        if FileManager.default.fileExists(atPath: auxiliaryStorageURL.path) {
            return VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        } else {
            return try generateAuxiliaryStorage(hardwareModel: hardwareModel)
        }
    }

    @discardableResult
    func generateAuxiliaryStorage(hardwareModel: VZMacHardwareModel? = nil) throws -> VZMacAuxiliaryStorage {
        if FileManager.default.fileExists(atPath: auxiliaryStorageURL.path) {
            try FileManager.default.removeItem(at: auxiliaryStorageURL)
        }

        let hw: VZMacHardwareModel
        if let hardwareModel {
            hw = hardwareModel
        } else {
            hw = try fetchOrGenerateHardwareModel(with: nil)
        }

        return try VZMacAuxiliaryStorage(
            creatingStorageAt: auxiliaryStorageURL,
            hardwareModel: hw
        )
    }

    func fetchOrGenerateHardwareModel(with restoreImage: VZMacOSRestoreImage?) throws -> VZMacHardwareModel {
        let hardwareModel: VZMacHardwareModel

        if FileManager.default.fileExists(atPath: hardwareModelURL.path) {
            guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
                throw Failure("Failed to retrieve hardware model data.")
            }

            guard let hw = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
                throw Failure("Failed to create hardware model.")
            }

            hardwareModel = hw
        } else {
            guard let image = restoreImage else {
                throw Failure("Hardware model data doesn't exist, but a restore image was not provided to create the initial data.")
            }

            guard let hw = image.mostFeaturefulSupportedConfiguration?.hardwareModel else {
                throw Failure("Failed to obtain hardware model from restore image")
            }

            hardwareModel = hw

            try hw.dataRepresentation.write(to: hardwareModelURL)
        }

        guard hardwareModel.isSupported else {
            throw Failure("The hardware model is not supported on the current host")
        }

        return hardwareModel
    }

    func fetchExistingMachineIdentifier() throws -> VZMacMachineIdentifier {
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            throw Failure("Failed to retrieve machine identifier data.")
        }

        guard let mid = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw Failure("Failed to create machine identifier.")
        }

        return mid
    }

    func fetchOrGenerateMachineIdentifier() throws -> VZMacMachineIdentifier {
        let identifier: VZMacMachineIdentifier

        if FileManager.default.fileExists(atPath: machineIdentifierURL.path) {
            identifier = try fetchExistingMachineIdentifier()
        } else {
            identifier = try generateNewMachineIdentifier()
        }

        return identifier
    }

    @discardableResult
    func generateNewMachineIdentifier() throws -> VZMacMachineIdentifier {
        if FileManager.default.fileExists(atPath: machineIdentifierURL.path) {
            try FileManager.default.removeItem(at: machineIdentifierURL)
        }

        let identifier = VZMacMachineIdentifier()

        try identifier.dataRepresentation.write(to: machineIdentifierURL)

        return identifier
    }

}

public extension VBVirtualMachine {
    var ECID: UInt64? {
        guard let machineIdentifier = try? self.fetchExistingMachineIdentifier() else { return nil }
        let data = machineIdentifier.dataRepresentation
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return dict["ECID"] as? UInt64
    }
}
