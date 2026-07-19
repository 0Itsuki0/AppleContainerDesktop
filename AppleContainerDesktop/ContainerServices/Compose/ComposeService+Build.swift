//
//  ComposeService+Build.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/12.
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS
import DockerComposeParser
import Foundation

extension ComposeService {

    // Build compose
    // - services that uses local docker file
    static func buildCompose(
        _ baseCompose: URL,
        additionalComposes: [URL] = [],
        // envs for parsing vars in the compose files
        envFiles: [URL] = [],
        projectDirectory: URL? = nil,
        nameOverride: String? = nil,
        // Services to build (builds all if omitted)
        // Explicitly targeting a service by name is an absolute override.
        // and always bypasses profile restrictions
        requestedServices: [String] = [],
        // Specify a profile to enable. Can be repeated.
        // Services without a 'profiles' key are always enabled;
        // profiled services are enabled only when one of their profiles is active.
        requestedProfiles: [String] = [],
        shouldRebuild: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let projectDirectory =
            projectDirectory ?? baseCompose.parentDirectory

        // all relative file path as well as any variables used in the YAML will be resolved
        let compose = try ComposeParser.loadComposes(
            baseCompose,
            otherComposes: additionalComposes,
            envFiles: envFiles,
            projectDirectory: projectDirectory,
            nameOverride: nameOverride
        )

        let name = resolveProjectName(
            projectDirectory: projectDirectory,
            compose: compose,
            nameOverride: nameOverride
        )

        messageStreamContinuation?.yield(
            "Building compose: \(name)..."
        )

        // service that needs to be built
        let servicesToBuild: [(serviceName: String, service: Service)] =
            try getServicesToBuild(
                compose: compose,
                requestedServices: requestedServices,
                requestedProfiles: requestedProfiles
            )

        messageStreamContinuation?.yield(
            "Building \(servicesToBuild.count) services..."
        )

        let response = await buildServices(
            servicesToBuild,
            secrets: compose.secrets?.removeNilValue() ?? [:],
            shouldRebuild: shouldRebuild,
            messageStreamContinuation: messageStreamContinuation
        )

        if !response.failedService.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to build one or more services. \n\(response.failedService.joined(separator: "\n"))"
            )
        }

        messageStreamContinuation?.yield("Build complete!")
        return
    }

    static func buildServices(
        _ servicesToBuild: [(String, Service)],
        secrets: [String: Secret],
        shouldRebuild: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async -> (successService: [String], failedService: [String]) {
        var success: [String] = []
        var failed: [String] = []

        await withTaskGroup(
            of: (String, Bool).self
        ) { [servicesToBuild] group in

            for (serviceName, service) in servicesToBuild {
                group.addTask { [serviceName, service] in
                    do {
                        messageStreamContinuation?.yield(
                            "Building service \(serviceName)..."
                        )

                        let _ = try await buildService(
                            service,
                            serviceName: serviceName,
                            shouldRebuild: shouldRebuild,
                            secrets: secrets,
                            messageStreamContinuation: servicesToBuild.count > 1
                                ? nil : messageStreamContinuation
                        )
                        return (serviceName, true)
                    } catch (let error) {
                        messageStreamContinuation?.yield(
                            "failed to build service \(serviceName): \(error)"
                        )
                        return (serviceName, false)
                    }
                }
            }

            for await result in group {
                if result.1 {
                    success.append(result.0)
                } else {
                    failed.append(result.0)
                }
            }
        }

        return (success, failed)
    }

    static func buildNetworks(
        _ networksToBuild: [(String, Network)],
        shouldRebuild: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async -> (
        networkResult: [NetworkResource], failedResource: [String]
    ) {
        var networkResult: [NetworkResource] = []
        var failedResource: [String] = []

        await withTaskGroup(
            of: (network: NetworkResource?, error: String?).self
        ) { [networksToBuild] group in

            for (networkName, network) in networksToBuild {
                group.addTask { [networkName, network] in
                    do {
                        messageStreamContinuation?.yield(
                            "Building network \(network.name ?? networkName)."
                        )
                        let network = try await buildNetwork(
                            network,
                            shouldRebuild: shouldRebuild,
                            networkName: networkName
                        )
                        return (network, nil)
                    } catch (let error) {
                        messageStreamContinuation?.yield(
                            "failed to build network \(network.name ?? networkName): \(error)"
                        )
                        return (
                            nil,
                            "\(network.name ?? networkName): \(error)"
                        )
                    }
                }
            }

            for await result in group {
                if let network = result.network {
                    networkResult.append(network)
                    continue
                }
                if let error = result.error {
                    failedResource.append(error)
                }
            }
        }

        return (networkResult, failedResource)
    }

    // Only build local image from dockerfile.
    // - No application containers are created at all when running the build command.
    // - No remote images (unless included within the dockerfile) is pulled.
    //
    // Reason for not creating container: user should be able to `compose up` multiple instances
    // ex: `docker compose up --scale web=3 -d`: we still have 1 service (web), but Docker Compose will instantly spin up 3 distinct containers running side-by-side (project-web-1, project-web-2, and project-web-3).
    //
    // Note: Apple Container does not support setting the network containers connect to for the RUN instructions during build.
    // ie: the build.network parameter will be ignored.
    // https://docs.docker.com/reference/compose-file/build/#network
    static func buildService(
        _ service: Service,
        serviceName: String,
        shouldRebuild: Bool,
        secrets: [String: Secret],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> ClientImage {
        guard let build = service.build else {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Build is not defined on the service."
            )
        }

        if build.dockerfile_inline != nil, build.dockerfile != nil {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Dockerfile Inline and Dockerfile cannot coexist."
            )
        }

        let imageTag = service.image ?? "\(serviceName):latest"

        if let existing = try await shouldBuildImage(
            imageTag,
            shouldRebuild: shouldRebuild
        ) {
            return existing
        }

        let contextURL = URL(filePath: build.context)
        let defaultDockerfile = URL(
            filePath: "Dockerfile",
            relativeTo: contextURL
        )
        // build.dockerfile is already resolved to full absolute path
        let dockerURL =
            build.dockerfile.flatMap({ URL(filePath: $0) }) ?? defaultDockerfile

        let dockerFileData: Data =
            if let dockerfileInline = build.dockerfile_inline {
                Data(dockerfileInline.utf8)
            } else {
                try Data(contentsOf: dockerURL)
            }

        // NOTE: services.<service>.environment and services.<service>.env_file are not passed in here
        // as they are environments for the container, not the image.
        let buildArgs = (build.args ?? [:]).removeNilValue().map({
            AdditionalUtility.keyValueString(key: $0.key, value: $0.value)
        })

        let labels = (build.labels ?? [:]).removeNilValue().map({
            AdditionalUtility.keyValueString(key: $0.key, value: $0.value)
        })

        let platform = try resolveBuildPlatforms(
            servicePlatform: service.platform,
            buildPlatforms: build.platforms
        )

        let cpuCount: Int64 =
            service.deploy?.resources?.limits?.cpus.map({ Int64($0) ?? 4 }) ?? 4
        let memoryInBytes =
            try service.deploy?.resources?.limits?.memory.map({
                try Parser.memoryStringAsMiB($0).mib()
            }) ?? 1024.mib()

        // secret name, target
        let serviceSecrets: [(String, String)] = (service.secrets ?? [])
            .compactMap({ ($0.source, $0.target ?? $0.source) })

        let buildSecrets: [(String, String)] = (build.secrets ?? [])
            .compactMap({ ($0.source, $0.target ?? $0.source) })

        // (target, file data)
        var resolvedSecret: [(String, Data)] = []
        // build comes later to take precedency
        for (secretName, target) in serviceSecrets + buildSecrets {
            guard let secret = secrets[secretName] else {
                continue
            }
            if secret.file != nil, secret.environment != nil {
                throw ContainerizationError(
                    .invalidArgument,
                    message:
                        "Secret cannot have both file and environment simultaneously."
                )
            }

            if let secretFile = secret.file {
                // file path is already absolute
                let url = URL(filePath: secretFile)
                resolvedSecret.append((target, try Data(contentsOf: url)))
                continue
            }

            if let environment = secret.environment {
                // Using getenv/strlen over processInfo.environment to support
                // non-UTF-8 env var data.
                guard let ptr = getenv(environment) else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "secret env \(environment) doesn't exist."
                    )
                }
                resolvedSecret.append(
                    (target, Data(bytes: ptr, count: strlen(ptr)))
                )
                continue
            }
        }

        try await ImageService.buildImage(
            dockerFileData: dockerFileData,
            contextDirectory: contextURL,
            tag: imageTag,
            cpus: cpuCount,
            memory: memoryInBytes,
            platforms: Set(platform),
            buildArguments: buildArgs,
            secrets: Dictionary(
                resolvedSecret,
                // later (defined in build) takes precedency
                uniquingKeysWith: { _, new in new }
            ),
            labels: labels,
            noCache: build.no_cache ?? false,
            targetStage: build.target ?? "",
            cacheIn: (build.cache_from ?? []).map(\.stringRepresentation)
                .removeNilValue(),
            cacheOut: (build.cache_to ?? []).map(\.stringRepresentation)
                .removeNilValue(),
            messageStreamContinuation: messageStreamContinuation
        )

        let image = try await ImageService.getImage(imageTag)

        return image
    }

    // https://docs.docker.com/reference/compose-file/build/#platforms
    private static func resolveBuildPlatforms(
        servicePlatform: Service.Platform?,
        buildPlatforms: [Service.Platform]?
    ) throws -> [Platform] {
        // When the list is non-empty and does not contain the service's platform.
        if let servicePlatform, let buildPlatforms, !buildPlatforms.isEmpty,
            !buildPlatforms.contains(servicePlatform)
        {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Build platforms must contain the service's platform when specified"
            )
        }
        if let buildPlatforms, !buildPlatforms.isEmpty {
            return buildPlatforms.map({
                $0.containerPlatform
            })
        }

        return [servicePlatform?.containerPlatform ?? Platform.current]
    }

    // NOTE: not passing in messageStreamContinuation here to avoid message overheads
    private static func buildNetwork(
        _ network: Network,
        shouldRebuild: Bool,
        networkName: String
    )
        async throws -> NetworkResource
    {
        if let external = network.external {
            guard !external else {
                throw ContainerizationError(
                    .invalidArgument,
                    message:
                        "Cannot build external network."
                )
            }
        }

        let name = network.name ?? networkName
        if let existing = try await shouldBuildNetwork(
            name,
            shouldRebuild: shouldRebuild
        ) {
            return existing
        }

        if network.enable_ipv4 == true, network.ipv4 == nil {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Container requires explicit IPv4 address when enabled."
            )
        }

        if network.enable_ipv6 == true, network.ipv6 == nil {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Container requires explicit IPv6 address when enabled."
            )
        }

        let ipv4: CIDRv4? =
            if let ipv4 = network.ipv4 { try CIDRv4(ipv4) } else { nil }
        let ipv6: CIDRv6? =
            if let ipv6 = network.ipv6 { try CIDRv6(ipv6) } else { nil }

        return try await NetworkService.createNetwork(
            name: name,
            internal: network.internal ?? false,
            labels: network.labels?.removeNilValue() ?? [:],
            options: network.driver_opts?.removeNilValue() ?? [:],
            ipv4Subnet: (network.enable_ipv4 ?? false) ? ipv4 : nil,
            ipv6Subnet: (network.enable_ipv6 ?? false) ? ipv6 : nil,
            messageStreamContinuation: nil
        )
    }

    // External volume (https://docs.docker.com/reference/compose-file/volumes/#external) will not be passed in.
    // NOTE: not passing in messageStreamContinuation here to avoid message overheads
    static func buildVolume(
        _ volume: Volume,
        shouldRebuild: Bool,
        volumeName: String
    )
        async throws -> VolumeConfiguration
    {
        if let external = volume.external {
            guard !external else {
                throw ContainerizationError(
                    .invalidArgument,
                    message:
                        "Cannot build external volume."
                )
            }
        }
        let name = volume.name ?? volumeName

        if let existing = try await shouldBuildVolume(
            name,
            shouldRebuild: shouldRebuild
        ) {
            return existing
        }

        return try await VolumeService.createVolume(
            name: name,
            driver: volume.driver ?? "local",
            labels: volume.labels?.removeNilValue() ?? [:],
            options: volume.driver_opts?.removeNilValue() ?? [:],
            size: nil,
            messageStreamContinuation: nil
        )
    }

    // return nil if should build
    private static func shouldBuildVolume(_ name: String, shouldRebuild: Bool)
        async throws -> VolumeConfiguration?
    {
        guard shouldRebuild == false else {
            // delete existing if there is any
            try? await VolumeService.deleteVolumes(
                [name],
                messageStreamContinuation: nil
            )
            return nil
        }
        do {
            return try await VolumeService.getVolume(name)
        } catch (let error) {
            guard let error = error as? ContainerizationError else {
                throw error
            }
            if error.code == .notFound {
                return nil
            }
            throw error
        }
    }

    private static func shouldBuildNetwork(_ name: String, shouldRebuild: Bool)
        async throws -> NetworkResource?
    {
        guard shouldRebuild == false else {
            try? await NetworkService.deleteNetworks(
                [name],
                messageStreamContinuation: nil
            )
            return nil
        }
        do {
            return try await NetworkService.getNetwork(name)
        } catch (let error) {
            guard let error = error as? ContainerizationError else {
                throw error
            }
            if error.code == .notFound {
                return nil
            }
            throw error
        }
    }

    private static func shouldBuildImage(_ name: String, shouldRebuild: Bool)
        async throws -> ClientImage?
    {
        guard shouldRebuild == false else {
            try? await ImageService.deleteImages(
                [name],
                messageStreamContinuation: nil
            )
            return nil
        }
        do {
            return try await ImageService.getImage(name)
        } catch (let error) {
            guard let error = error as? ContainerizationError else {
                throw error
            }
            if error.code == .notFound {
                return nil
            }
            throw error
        }
    }

    private static func getServicesToBuild(
        compose: DockerCompose,
        requestedServices: [String],
        requestedProfiles: [String],
    ) throws -> [(serviceName: String, service: Service)] {
        // service that is either part of the active profile or requested service
        let selectedNames = Set(
            try selectServicesForUpBuild(
                compose: compose,
                requestedServices: requestedServices,
                requestedProfiles: requestedProfiles,
            )
            .map(\.serviceName)
        )

        // service that needs to be built
        let servicesToBuild: [(serviceName: String, service: Service)] = compose
            .services.compactMap { name, service in
                guard let service, service.build != nil,
                    selectedNames.contains(name)
                else { return nil }
                return (name, service)
            }

        return servicesToBuild
    }
}
