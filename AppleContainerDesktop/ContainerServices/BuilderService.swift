//
//  BuilderService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/18.
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
import Foundation

class BuilderService {

    static let buildkitContainerId = "buildkit"
    static private let containerSystemConfig = ContainerSystemConfig()

    // memory: bytes
    static func startBuilder(
        cpus: Int64 = 2,
        memory: UInt64 = 1024.mib(),
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        messageStreamContinuation?.yield("Fetching BuildKit image...")

        let builderImage: String = containerSystemConfig.build.image
        let systemHealth = try await ClientHealthCheck.ping(
            timeout: .seconds(10)
        )
        let exportsMount: String = systemHealth.appRoot.appendingPathComponent(
            ".build"
        ).absolutePath

        if !FileManager.default.fileExists(atPath: exportsMount) {
            try FileManager.default.createDirectory(
                atPath: exportsMount,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let builderPlatform = ContainerizationOCI.Platform(
            arch: "arm64",
            os: "linux",
            variant: "v8"
        )
        
        var targetEnvVars: [String] = []
        if let buildkitColors = ProcessInfo.processInfo.environment["BUILDKIT_COLORS"] {
            targetEnvVars.append("BUILDKIT_COLORS=\(buildkitColors)")
        }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
            targetEnvVars.append("NO_COLOR=true")
        }
        targetEnvVars.sort()

        let client = ContainerClient()
        let existingContainer = try? await client.get(id: buildkitContainerId)

        if let existingContainer {
            let existingImage = existingContainer.configuration.image.reference
            let existingResources = existingContainer.configuration.resources
            let existingEnv = existingContainer.configuration.initProcess
                .environment
            // let existingDNS = existingContainer.configuration.dns

            let existingManagedEnv = existingEnv.filter { envVar in
                envVar.hasPrefix("BUILDKIT_COLORS=") || envVar.hasPrefix("NO_COLOR=")
            }.sorted()

            // Check if we need to recreate the builder due to different image
            let imageChanged = existingImage != builderImage
            let cpuChanged = existingResources.cpus != cpus
            let memChanged = existingResources.memoryInBytes != memory
            let envChanged = existingManagedEnv != targetEnvVars


            switch existingContainer.status {
            case .running:
                guard imageChanged || cpuChanged || memChanged || envChanged else {
                    // If image, mem, cpu, env, and DNS are the same, continue using the existing builder
                    return
                }
                // If they changed, stop and delete the existing builder
                try await client.stop(id: existingContainer.id)
                try await client.delete(id: existingContainer.id)
            case .stopped:
                // If the builder is stopped and matches our requirements, start it
                // Otherwise, delete it and create a new one
                guard imageChanged || cpuChanged || memChanged || envChanged else {
                    try await startBuildKit(
                        client: client,
                        id: existingContainer.id,
                        messageStreamContinuation: messageStreamContinuation
                    )
                    return
                }
                try await client.delete(id: existingContainer.id)
            case .stopping:
                throw ContainerizationError(
                    .invalidState,
                    message:
                        "builder is stopping, please wait until it is fully stopped before proceeding"
                )
            case .unknown:
                break
            }
        }

        let shimArguments: [String] = [
            "--debug",
            "--vsock",
        ]

        try ContainerAPIClient.Utility.validEntityName(
            Builder.builderContainerId
        )

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
            containerSystemConfig: containerSystemConfig,
            progressUpdate: { events in
                AdditionalUtility.updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        // Unpack fetched image before use
        messageStreamContinuation?.yield("Unpacking BuildKit image...")

        _ = try await image.getCreateSnapshot(
            platform: builderPlatform,
            progressUpdate: { events in
                AdditionalUtility.updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        let imageConfig = ImageDescription(
            reference: builderImage,
            descriptor: image.descriptor
        )

        var config = ContainerConfiguration(
            id: buildkitContainerId,
            image: imageConfig,
            process: processConfig
        )
        config.resources = resources
        config.labels = [
            ResourceLabelKeys.plugin: "builder",
            ResourceLabelKeys.role: ResourceRoleValues.builder,
        ]
        config.capAdd = ["ALL"]
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
        config.rosetta = true

        let networkClient = NetworkClient()
        guard let defaultNetwork = try await networkClient.builtin else {
            throw ContainerizationError(
                .invalidState,
                message: "default network is not present"
            )
        }
        config.networks = [
            AttachmentConfiguration(
                network: defaultNetwork.id,
                options: AttachmentOptions(hostname: Builder.builderContainerId)
            )
        ]

        let nameServer = IPv4Address(
            defaultNetwork.status.ipv4Subnet.lower.value + 1
        ).description
        let nameServers = [nameServer]
        config.dns = ContainerConfiguration.DNSConfiguration(
            nameservers: nameServers
        )

        let kernel = try await {
            messageStreamContinuation?.yield("Fetching kernel...")
            let kernel = try await ClientKernel.getDefaultKernel(for: .current)
            return kernel
        }()

        messageStreamContinuation?.yield("Creating BuildKit container...")

        try await client.create(
            configuration: config,
            options: .default,
            kernel: kernel
        )
        try await startBuildKit(
            client: client,
            id: Builder.builderContainerId,
            messageStreamContinuation: messageStreamContinuation
        )

        messageStreamContinuation?.yield("Builder started...")

    }

    private static func startBuildKit(
        client: ContainerClient,
        id: String,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        messageStreamContinuation?.yield("Starting build kit...")

        do {
            let io = try ProcessIO.create(
                tty: false,
                interactive: false,
                detach: true
            )
            defer { try? io.close() }

            var dynamicEnv: [String: String] = [:]
            if let sshAuthSock = ProcessInfo.processInfo.environment[
                "SSH_AUTH_SOCK"
            ] {
                dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
            }

            messageStreamContinuation?.yield(
                "Bootstrapping buildkit container..."
            )

            let process = try await client.bootstrap(
                id: id,
                stdio: io.stdio,
                dynamicEnv: dynamicEnv
            )
            _ = try await process.start()
            try io.closeAfterStart()

        } catch {
            try? await client.stop(id: id)
            try? await client.delete(id: id)
            if error is ContainerizationError {
                throw error
            }
            throw ContainerizationError(
                .internalError,
                message: "failed to start BuildKit: \(error)"
            )
        }
    }
}
