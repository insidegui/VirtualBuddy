import Foundation

/// Copies disk images that live outside of a virtual machine into its bundle so that they can be part of its saved session.
public struct ExternalDiskImageCopier: Sendable {
    /// The result of copying. Nothing refers to the copies until the caller applies ``devices`` to the virtual machine's configuration.
    ///
    /// `@unchecked Sendable` because the devices are plain values that are never mutated after copying.
    public struct Result: @unchecked Sendable {
        /// The storage devices of the virtual machine, in their original order and with their original identities,
        /// where every external disk image is now backed by a copy in the bundle.
        public internal(set) var devices: [VBStorageDevice]
        fileprivate let convertedDeviceIDs: Set<String>
        fileprivate let copiedURLs: [URL]
        fileprivate let fileSystem: SavedSessionFileSystem

        /// Removes the copies. Call this if the new configuration could not be saved.
        public func discardCopies() {
            for url in copiedURLs {
                try? fileSystem.remove(url)
            }
        }
    }

    let fileSystem: SavedSessionFileSystem

    public init() {
        self.fileSystem = DefaultSavedSessionFileSystem()
    }

    init(fileSystem: SavedSessionFileSystem) {
        self.fileSystem = fileSystem
    }

    /// Whether the virtual machine has disk images stored outside of its bundle.
    public static func externalDevices(of model: VBVirtualMachine) -> [VBStorageDevice] {
        model.configuration.hardware.storageDevices.filter {
            if case .customImage = $0.backing { return true } else { return false }
        }
    }

    /// Copies every external disk image into the bundle, leaving the originals alone.
    ///
    /// Either all of them are copied or none are: a failure removes everything that was copied.
    public func copyExternalDiskImages(of model: VBVirtualMachine) async throws -> Result {
        let fileSystem = self.fileSystem

        var result = try await performOffMainActor { try Self.copy(model: model, fileSystem: fileSystem) }

        /// The size of an image that isn't raw can't be derived from the size of its file.
        var devices = [VBStorageDevice]()
        for var device in result.devices {
            if result.convertedDeviceIDs.contains(device.id),
               case .managedImage(var image) = device.backing,
               image.format == .sparse,
               let capacity = try? await VBDiskResizer.currentImageSize(at: model.diskImageURL(for: image), format: image.format)
            {
                image.size = capacity
                device.backing = .managedImage(image)
            }
            devices.append(device)
        }
        result.devices = devices

        return result
    }

    private static func copy(model: VBVirtualMachine, fileSystem: SavedSessionFileSystem) throws -> Result {
        let bundleURL = model.bundleURL
        let workURL = bundleURL.appending(path: ".disk-copy-\(UUID().uuidString)", directoryHint: .isDirectory)

        var finalURLs = [URL]()
        var usedNames = Set<String>(try fileSystem.contentsOfDirectory(at: bundleURL).map { $0.lastPathComponent.lowercased() })

        do {
            try fileSystem.createDirectory(workURL)

            var plan = [(deviceID: String, workURL: URL, finalURL: URL, image: VBManagedDiskImage)]()

            for device in model.configuration.hardware.storageDevices {
                guard case .customImage(let sourceURL) = device.backing else { continue }

                try Task.checkCancellation()

                guard fileSystem.exists(sourceURL) else {
                    throw Failure("The disk image \"\(sourceURL.lastPathComponent)\" could not be found.")
                }

                let format = VBManagedDiskImage.Format(copying: sourceURL)
                let baseName = sourceURL.deletingPathExtension().lastPathComponent

                var filename = baseName
                var attempt = 1
                while usedNames.contains("\(filename).\(format.fileExtension)".lowercased()) {
                    attempt += 1
                    filename = "\(baseName) \(attempt)"
                }
                usedNames.insert("\(filename).\(format.fileExtension)".lowercased())

                let stagedURL = workURL.appending(path: "\(plan.count)")
                try fileSystem.copy(from: sourceURL, to: stagedURL)

                let size = fileSystem.byteCount(of: stagedURL) ?? 0
                let image = VBManagedDiskImage(filename: filename, size: size, format: format)

                plan.append((device.id, stagedURL, bundleURL.appending(path: "\(filename).\(format.fileExtension)"), image))
            }

            /// Every copy exists, now they're moved to their final names.
            for item in plan {
                try fileSystem.move(from: item.workURL, to: item.finalURL, replacingExisting: false)
                finalURLs.append(item.finalURL)
            }

            try fileSystem.remove(workURL)

            let images = Dictionary(uniqueKeysWithValues: plan.map { ($0.deviceID, $0.image) })

            let devices = model.configuration.hardware.storageDevices.map { device -> VBStorageDevice in
                guard let image = images[device.id] else { return device }

                var converted = device
                converted.backing = .managedImage(image)
                return converted
            }

            return Result(devices: devices, convertedDeviceIDs: Set(images.keys), copiedURLs: finalURLs, fileSystem: fileSystem)
        } catch {
            for url in finalURLs {
                try? fileSystem.remove(url)
            }
            try? fileSystem.remove(workURL)
            throw error
        }
    }
}

private extension VBManagedDiskImage.Format {
    /// The managed format that can hold a copy of the file. Anything that isn't a known image format is treated as a raw image.
    init(copying url: URL) {
        switch url.pathExtension.lowercased() {
        case "dmg": self = .dmg
        case "sparseimage": self = .sparse
        case "asif": self = .asif
        default: self = .raw
        }
    }
}
