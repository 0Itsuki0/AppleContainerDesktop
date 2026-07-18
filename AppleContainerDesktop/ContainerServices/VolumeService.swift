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

enum VolumeService {

    // labels: metadata for a volume
    // Options: driver specific options
    // Size: Size of the volume in bytes, with optional K, M, G, T, or P suffix
    @discardableResult
    static func createVolume(
        name: String,
        driver: String = "local",
        labels: [String: String] = [:],
        options: [String: String] = [:],
        size: (UInt64, SizeType)? = nil,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> VolumeConfiguration {
        messageStreamContinuation?.yield("Creating volume: \(name)...")

        var driverOptions = options
        if let size = size {
            driverOptions[VolumeConfiguration.sizeOptionKey] =
                "\(size.0)\(size.1.suffix)"
        }

        let volume = try await ClientVolume.create(
            name: name,
            driver: driver,
            driverOpts: driverOptions,
            labels: labels
        )

        messageStreamContinuation?.yield("Volume created: \(volume.id)")

        return volume
    }

    static func listVolumes() async throws -> [VolumeConfiguration] {
        let volumes = try await ClientVolume.list()
        return volumes
    }

    // Memo: VolumeConfiguration to VolumeResource
    // let volumeResources = volumes.map { VolumeResource(configuration: $0) }
    // NOTE: not using ClientVolume.inspect() to handle the notFound case specifically
    static func getVolume(_ name: String) async throws -> VolumeConfiguration {
        // for volumes, id and name are the same
        guard
            let volume = try await listVolumes().first(where: {
                $0.name == name
            })
        else {
            throw ContainerizationError(
                .notFound,
                message: "volume not found: \(name)"
            )
        }
        return volume
    }

    static func deleteVolumes(
        _ volumes: [String],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let volumes = try await self.listVolumes().filter({
            volumes.contains($0.name)
        })
        guard !volumes.isEmpty else {
            return
        }
        try await self.deleteVolumes(
            volumes,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    static func deleteVolumes(
        _ volumes: [VolumeConfiguration],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        messageStreamContinuation?.yield(
            "Deleting \(volumes.count) Volume(s)..."
        )

        var failed: [(String, Error)] = []

        await withTaskGroup(of: (String, Error)?.self) { group in
            for volume in volumes {
                group.addTask {
                    do {
                        try await ClientVolume.delete(name: volume.id)
                        messageStreamContinuation?.yield(
                            "Volume deleted: \(volume.id)"
                        )
                        return nil
                    } catch {
                        if error.isResourceNotFound {
                            return nil
                        }
                        messageStreamContinuation?.yield(
                            "failed to delete container \(volume.id): \(error)"
                        )
                        return (volume.id, error)
                    }
                }
            }

            for await result in group {
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
