//
//  VolumeService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/11/03.
//

import ContainerAPIClient
import ContainerBuild
import ContainerPersistence
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS

class VolumeService {

    // labels: metadata for a volume
    // Options: driver specific options
    // Size: Size of the volume in bytes, with optional K, M, G, T, or P suffix
    @discardableResult
    static func createVolume(
        name: String,
        labels: [KeyValueModel],
        options: [KeyValueModel],
        size: (UInt64, SizeType)?,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> VolumeConfiguration {
        messageStreamContinuation?.yield("Creating volume: \(name)...")

        var driverOptions = options.dictRepresentation
        if let size = size {
            driverOptions[VolumeConfiguration.sizeOptionKey] = "\(size.0)\(size.1.suffix)"
        }

        let volume = try await ClientVolume.create(
            name: name,
            driver: "local",
            driverOpts: driverOptions,
            labels: labels.dictRepresentation
        )

        messageStreamContinuation?.yield("Volume created: \(volume.id)")

        return volume
    }

    static func listVolumes() async throws -> [VolumeConfiguration] {
        let volumes = try await ClientVolume.list()
        return volumes
    }

    static func deleteVolumes(
        _ volumes: [VolumeConfiguration],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        messageStreamContinuation?.yield(
            "Deleting \(volumes.count) Volume(s)..."
        )

        var failed: [(String, Error)] = []

        try await withThrowingTaskGroup(of: (String, Error)?.self) { group in
            for volume in volumes {
                group.addTask {
                    do {
                        try await ClientVolume.delete(name: volume.id)
                        messageStreamContinuation?.yield(
                            "Volume deleted: \(volume.id)"
                        )
                        return nil
                    } catch {
                        messageStreamContinuation?.yield(
                            "failed to delete container \(volume.id): \(error)"
                        )
                        return (volume.id, error)
                    }
                }
            }

            for try await result in group {
                guard let result else {
                    continue
                }
                failed.append((result.0, result.1))
            }
        }

        if failed.count > 0 {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to delete one or more volumes: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }

    }

}
