//
//  BuilderService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/18.
//

import Foundation

import ContainerBuild
import ContainerClient
import ContainerNetworkService
import ContainerPersistence
import Containerization
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS

class BuilderService {
    
    static let buildkitContainerId = "buildkit"
    
    // memory: bytes
    static func startBuilder(cpus: Int64 = 2, memory: UInt64 = 1024.mib(), messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {
        messageStreamContinuation?.yield("Fetching BuildKit image...")

        let builderImage: String = DefaultsStore.get(key: .defaultBuilderImage)
        let systemHealth = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let exportsMount: String = systemHealth.appRoot.appendingPathComponent(".build").absolutePath

        if !FileManager.default.fileExists(atPath: exportsMount) {
            try FileManager.default.createDirectory(
                atPath: exportsMount,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let builderPlatform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

        let existingContainer = try? await ClientContainer.get(id: buildkitContainerId)

        if let existingContainer {
            let existingImage = existingContainer.configuration.image.reference
            let existingResources = existingContainer.configuration.resources

            // Check if we need to recreate the builder due to different image
            let imageChanged = existingImage != builderImage
            let cpuChanged = existingResources.cpus != cpus
            let memChanged = existingResources.memoryInBytes != memory

            switch existingContainer.status {
            case .running:
                guard imageChanged || cpuChanged || memChanged else {
                    // If image, mem and cpu are the same, continue using the existing builder
                    return
                }
                // If they changed, stop and delete the existing builder
                try await existingContainer.stop()
                try await existingContainer.delete()
            case .stopped:
                // If the builder is stopped and matches our requirements, start it
                // Otherwise, delete it and create a new one
                guard imageChanged || cpuChanged || memChanged else {
                    try await startBuildKit(existingContainer, messageStreamContinuation: messageStreamContinuation)
                    return
                }
                try await existingContainer.delete()
            case .stopping:
                throw ContainerizationError(
                    .invalidState,
                    message: "builder is stopping, please wait until it is fully stopped before proceeding"
                )
            case .unknown:
                break
            }
        }

        let shimArguments: [String] = [
            "--debug",
            "--vsock",
        ]

        try ContainerClient.Utility.validEntityName(buildkitContainerId)

        let processConfig = ProcessConfiguration(
            executable: "/usr/local/bin/container-builder-shim",
            arguments: shimArguments,
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0)
        )

        var resources = ContainerConfiguration.Resources()
        resources.cpus = Int(cpus)
        resources.memoryInBytes = memory

        let image = try await ClientImage.fetch(
            reference: builderImage,
            platform: builderPlatform,
            progressUpdate: { events in
                Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )
        
        // Unpack fetched image before use
        messageStreamContinuation?.yield("Unpacking BuildKit image...")
        
        _ = try await image.getCreateSnapshot(
            platform: builderPlatform,
            progressUpdate: { events in
                Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )
        
        let imageConfig = ImageDescription(
            reference: builderImage,
            descriptor: image.descriptor
        )

        var config = ContainerConfiguration(id: buildkitContainerId, image: imageConfig, process: processConfig)
        config.resources = resources
        config.mounts = [
            .init(
                type: .tmpfs,
                source: "",
                destination: "/run",
                options: []
            ),
            .init(
                type: .virtiofs,
                source: exportsMount,
                destination: "/var/lib/container-builder-shim/exports",
                options: []
            ),
        ]
        // Enable Rosetta only if the user didn't ask to disable it
        config.rosetta = DefaultsStore.getBool(key: .buildRosetta) ?? true

        let network = try await ClientNetwork.get(id: ClientNetwork.defaultNetworkName)

        guard case .running(_, let networkStatus) = network else {
            return
        }

        
        config.networks = [AttachmentConfiguration(network: network.id, options: AttachmentOptions(hostname: buildkitContainerId))]
        let subnet = try CIDRAddress(networkStatus.address)
        let nameServer = IPv4Address(fromValue: subnet.lower.value + 1).description
        let nameServers = [nameServer]
        config.dns = ContainerConfiguration.DNSConfiguration(nameservers: nameServers)

        let kernel = try await {
            messageStreamContinuation?.yield("Fetching kernel...")
            let kernel = try await ClientKernel.getDefaultKernel(for: .current)
            return kernel
        }()

        messageStreamContinuation?.yield("Creating BuildKit container...")

        let container = try await ClientContainer.create(
            configuration: config,
            options: .default,
            kernel: kernel
        )

        try await startBuildKit(container, messageStreamContinuation: messageStreamContinuation)
        
        messageStreamContinuation?.yield("Builder started...")

    }
    
    
    private static func startBuildKit(_ container: ClientContainer, messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {
        messageStreamContinuation?.yield("Starting build kit...")

        guard container.id == buildkitContainerId else {
            return
        }
        do {
            let io = try ProcessIO.create(
                tty: false,
                interactive: false,
                detach: true
            )
            defer { try? io.close() }

            messageStreamContinuation?.yield("Bootstrapping buildkit container...")

            let process = try await container.bootstrap(stdio: io.stdio)

            _ = try await process.start()
            try io.closeAfterStart()

        } catch {
            try? await container.stop()
            try? await container.delete()
            if error is ContainerizationError {
                throw error
            }
            throw ContainerizationError(.internalError, message: "failed to start BuildKit: \(error)")
        }
    }
    
    
}
