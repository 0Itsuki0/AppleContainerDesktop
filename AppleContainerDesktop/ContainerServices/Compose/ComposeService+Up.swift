//
//  ComposeService+Up.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/12.
//

import ArgumentParser
import ContainerAPIClient
import ContainerResource
import ContainerXPC
import Containerization
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS
import DockerComposeParser
import Foundation
import NIOCore
import NIOPosix

extension ComposeService {

    // user should be able to `compose up` multiple instances
    // ex: `docker compose up --scale web=3 -d`: You still have 1 service (web), but Docker Compose will instantly spin up 3 distinct containers running side-by-side (project-web-1, project-web-2, and project-web-3).
    // -
    // Q: however, that would mean every time up is run there will be different container created which is not what I see
    // A: You are completely right to point that out, and what you are seeing is Docker Compose's built-in caching and optimization system at work.When you run docker compose up a second time, Docker Compose will reuse your existing container if nothing in your configuration has changed. It only destroys and creates a brand-new container if it absolutely has to.
    //
    // -
    // Q: so if I ran =3 the first time, and =1 the second time, then the remaining two are just dangling forever?
    // A: No, they are not left dangling forever. Docker Compose is smart enough to handle scaling states automatically.
    // Exactly What Happens When Scaling Down
    // 1. When you run a command to decrease the replica count, Docker Compose performs an immediate state reconciliation:Calculates the Difference: It looks at the host and sees 3 running containers (web-1, web-2, web-3), but notes your new command specifies a target count of 1.
    // 2. Gracefully Stops Them: It selects the extra 2 containers (typically the newest ones created) and sends them a termination signal (SIGTERM) to stop the application gracefully.
    // 3. Instantly Deletes Them: Once stopped, Docker Compose automatically deletes and removes those two container processes from the engine storage.
    //
    // Additive action
    // ie: if service A was started, and then B starts,
    // both A and B will be running
    //
    // Returning: ServiceName: List of containers created for the service
    static func upCompose(
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
        // only effect image
        forceRebuild: Bool,
        // effect volume and network
        forceRecreate: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> [String: [ContainerSnapshot]] {
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

        let projectName = resolveProjectName(
            projectDirectory: projectDirectory,
            composeName: compose.name,
            nameOverride: nameOverride
        )

        messageStreamContinuation?.yield(
            "Building compose: \(projectName)..."
        )
        let selectedServices = try selectServicesForUpBuild(
            compose: compose,
            requestedServices: requestedServices,
            requestedProfiles: requestedProfiles,
        )

        messageStreamContinuation?.yield(
            "Building \(selectedServices.count) services..."
        )

        let networks = compose.networks?.mapValues({ $0 ?? Network() }) ?? [:]
        let volumes = compose.volumes?.mapValues({ $0 ?? Volume() }) ?? [:]
        let secrets = compose.secrets?.mapValues({ $0 ?? Secret() }) ?? [:]

        var containersBuilt: [String: [ContainerSnapshot]] = [:]

        try await withThrowingTaskGroup(of: (String, [ContainerSnapshot]).self)
        { group in
            for (serviceName, service) in selectedServices {
                group.addTask {
                    let container = try await resolveServiceContainers(
                        service,
                        serviceName: serviceName,
                        networks: networks,
                        volumes: volumes,
                        secrets: secrets,
                        projectName: projectName,
                        rebuildImage: forceRebuild,
                        rebuildOtherResource: forceRecreate,
                        messageStreamContinuation: messageStreamContinuation
                    )
                    return (serviceName, container)
                }
            }

            for try await result in group {
                containersBuilt[result.0] = result.1
            }
        }

        messageStreamContinuation?.yield(
            "Finish building \(containersBuilt.count) containers..."
        )

        messageStreamContinuation?.yield(
            "Starting containers..."
        )

        // start service (containers) in order based on the depends_on field
        try await self.startServices(
            projectName: projectName,
            selectedServices: selectedServices,
            containerCreated: containersBuilt,
            messageStreamContinuation: messageStreamContinuation
        )

        messageStreamContinuation?.yield(
            "Compose up!"
        )

        return containersBuilt
    }

    private static func startServices(
        projectName: String,
        selectedServices: [(serviceName: String, service: Service)],
        containerCreated: [String: [ContainerSnapshot]],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let sortedStages = try topoSortConfiguredServices(selectedServices)

        messageStreamContinuation?.yield(
            "Stopping running containers..."
        )

        // NOTE: not stopping all containers here at once because they need to be stopped in the opposite order
        try await self.downServices(
            projectName: projectName,
            selectedServices: selectedServices,
            startedContainers: containerCreated.mapValues({ $0.map(\.id) }),
            shouldDelete: false,
            messageStreamContinuation: nil
        )

        for stage in sortedStages {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (serviceName, service, condition) in stage {
                    messageStreamContinuation?.yield(
                        "Starting containers for \(serviceName)..."
                    )

                    for var container in containerCreated[serviceName] ?? [] {
                        // since we have called downServices above, we need to manually set this to `.stopped`
                        // so that the `if container.status == .running` check in `ContainerService.startContainer` won't cause early return and fail to actually start the container
                        container.status = .stopped
                        group.addTask {
                            // start container detached
                            let exitCode =
                                try await ContainerService.startContainer(
                                    container,
                                    attachContainerStdout: false,
                                    attachContainerStdIn: false,
                                    messageStreamContinuation: nil
                                )

                            messageStreamContinuation?.yield(
                                "Container started with exit code \(exitCode, default: "(unknown)")..."
                            )

                            // wait for depend on condition before returning
                            try await waitForCondition(
                                condition,
                                containerID: container.id,
                                exitCode: exitCode,
                                service: service,
                                messageStreamContinuation:
                                    messageStreamContinuation
                            )
                            return
                        }
                    }

                }

                try await group.waitForAll()
            }
        }
    }

    private static func waitForCondition(
        _ condition: Service.DependencyCondition?,
        containerID: ContainerSnapshotID,
        exitCode: Int32?,
        service: Service,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        guard let condition else { return }

        messageStreamContinuation?.yield(
            "Waiting for \(condition) on \(containerID)..."
        )

        switch condition {
        case .service_started:
            try await waitForStart(
                containerID,
                exitCode: exitCode,
                hasToComplete: false
            )
        case .service_healthy:
            try await waitForHealthCheck(
                containerID,
                exitCode: exitCode,
                healthCheckConfiguration: service.healthcheck
            )
        case .service_completed_successfully:
            try await waitForStart(
                containerID,
                exitCode: exitCode,
                hasToComplete: true
            )
        }

        messageStreamContinuation?.yield(
            "\(condition) for \(containerID) met!"
        )
    }

    private static func waitForHealthCheck(
        _ containerId: ContainerSnapshotID,
        exitCode: Int32?,
        healthCheckConfiguration: Service.Healthcheck?
    )
        async throws
    {
        try await waitForStart(
            containerId,
            exitCode: exitCode,
            hasToComplete: false
        )

        if exitCode != nil {
            throw ContainerizationError(
                .invalidState,
                message: "Container is stopped before health check."
            )
        }

        guard let healthCheckConfiguration else { return }
        guard !healthCheckConfiguration.isDisabled else { return }

        guard let args = healthCheckConfiguration.execArguments else {
            return
        }
        let retries = max(healthCheckConfiguration.retries ?? 3, 1)
        let interval = Service.Healthcheck.parseDuration(
            healthCheckConfiguration.interval,
            default: 30
        )
        let startPeriod = Service.Healthcheck.parseDuration(
            healthCheckConfiguration.start_period,
            default: 0
        )
        if startPeriod > 0 {
            try await Task.sleep(
                nanoseconds: UInt64(startPeriod * 1_000_000_000)
            )
        }

        for attempt in 1...retries {
            do {
                let exitCode = try await ContainerService.executeCommand(
                    on: containerId,
                    arguments: args,
                    processFlags: .init(),
                    detach: false,
                    onStdout: nil,
                    onStderr: { error in
                        print("Std Error on healthcheck: \(error)")
                    }
                )
                if let exitCode, ArgumentParser.ExitCode(exitCode) == .success {
                    return
                }
            } catch {
                // not throwing here as we are retrying.
                print(
                    "Error executing command on attempt: \(attempt). Error: \(error)."
                )
            }
            if attempt < retries {
                try await Task.sleep(
                    nanoseconds: UInt64(interval * 1_000_000_000)
                )
            }
        }

        throw ContainerizationError(
            .invalidState,
            message: "Healthcheck failed for \(containerId)."
        )
    }

    // assume container starts detached
    // hasToComplete: false for `service_started`, true for `service_completed_successfully`
    private static func waitForStart(
        _ containerId: ContainerSnapshotID,
        timeoutMs: TimeInterval = 10_000,
        exitCode: Int32?,
        hasToComplete: Bool
    ) async throws {
        var elapsed: TimeInterval = 0
        let waitInterval: TimeInterval = 10
        while true {
            try await Task.sleep(for: .milliseconds(waitInterval))
            do {
                let container = try await ContainerService.getContainer(
                    containerId
                )

                if !hasToComplete {
                    if container.status == .running {
                        return
                    }
                }

                if container.status == .stopped {
                    var resolvedExitCode: Int32
                    if let exitCode {
                        resolvedExitCode = exitCode
                    } else {
                        resolvedExitCode = try await waitForExit(
                            containerId
                        )
                    }
                    guard ArgumentParser.ExitCode(resolvedExitCode) == .success
                    else {
                        throw ContainerizationError(
                            .invalidState,
                            message:
                                "Fail to wait for container \(containerId) to \(hasToComplete ? "complete" : "start") successfully."
                        )
                    }
                    return
                }
            } catch {
                // not throwing here as we are still waiting.
            }

            if elapsed > timeoutMs {
                throw ContainerizationError(
                    .timeout,
                    message:
                        "Time out waiting for container \(containerId) to \(hasToComplete ? "complete" : "start") successfully."
                )
            }
            elapsed += waitInterval
            continue
        }
    }

    private static func waitForExit(
        _ containerId: ContainerSnapshotID
    ) async throws -> Int32 {
        let request = XPCMessage(route: .containerWait)
        request.set(key: .id, value: containerId)
        request.set(key: .processIdentifier, value: containerId)
        let xpcClient = XPCClient(service: "com.apple.container.apiserver")
        let response = try await xpcClient.send(request)
        let code = response.int64(key: .exitCode)
        return Int32(code)
    }

    // get or create container
    private static func resolveServiceContainers(
        _ service: Service,
        serviceName: String,
        networks: [String: DockerComposeParser.Network],
        volumes: [String: Volume],
        secrets: [String: Secret],
        projectName: String,
        rebuildImage: Bool,
        rebuildOtherResource: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> [ContainerSnapshot] {
        let recreateContainer = rebuildOtherResource || rebuildImage

        let count = service.deploy?.replicas ?? 1
        // Compose does not scale a service beyond one container if the Compose file specifies a container_name. Attempting to do so results in an error.
        let container_name = service.container_name
        if container_name != nil, count > 1 {
            throw ContainerizationError(
                .invalidArgument,
                message: "Container with explicit name cannot be scaled."
            )
        }

        let image: String
        if service.build != nil {
            // docker
            messageStreamContinuation?.yield("Building image for service: \(serviceName)...")
            let clientImage = try await buildService(
                service,
                serviceName: serviceName,
                shouldRebuild: rebuildImage,
                secrets: secrets,
                messageStreamContinuation: messageStreamContinuation
            )
            image = clientImage.reference
        } else if let serviceImage = service.image {
            // remote
            messageStreamContinuation?.yield("Pulling image for service: \(serviceName)...")
            try await ImageService.pullImage(
                reference: serviceImage,
                platform: service.platform?.containerPlatform
                    ?? Platform.current,
                messageStreamContinuation: nil
            )
            image = serviceImage
        } else {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Image name is not specified for service: \(serviceName)"
            )
        }

        let containerNames: [String] = (1..<1 + count).map({ index in
            containerName(
                explicit: container_name,
                projectName: projectName,
                serviceName: serviceName,
                index: index,
                total: count
            )
        })

        // let config = service.configs
        let process = ContainerProcess(
            workingDirectory: service.working_dir,
            environments: service.environment?.removeNilValue().map({
                AdditionalUtility.keyValueString(key: $0.key, value: $0.value)
            }) ?? [],
            envFile: (service.env_file ?? []).map(\.path),
            tty: service.tty ?? false,
            uid: nil,
            gid: nil,
            user: nil
        )

        let baseManagement = ContainerManagement(
            entryPoint: service.entrypoint?.joined(separator: " "),
            virtualFileSystem: [],
            volumes: try await resolveServiceVolumes(
                service,
                shouldRebuild: rebuildOtherResource,
                topLevelVolume: volumes
            ),
            publishPorts: service.ports?.map(\.publishPort).removeNilValue()
                ?? [],
            publishSockets: [],
            temporaryFileSystem: resolveServiceTmpfs(service),
            // NOTE: name to be update for each container
            name: "",
            remove: false,
            platform: nil,
            os: service.platform?.os ?? "linux",
            arch: service.platform?.arch
                ?? Arch.hostArchitecture().rawValue,
            kernel: nil,
            networks: try await resolveContainerNetworks(
                service: service,
                networks: networks,
                shouldRebuild: rebuildOtherResource
            ),
            cidfile: "",
            // cannot entirely disable Docker's built-in embedded DNS server
            dnsDisabled: false,
            dnsNameservers: service.dns ?? [],
            dnsDomain: nil,
            dnsSearchDomains: service.dns_search ?? [],
            dnsOptions: service.dns_opt ?? [],
            labels: service.labels?.removeNilValue() ?? [:],
            virtualization: service.virtualization,
            ssh: false,
            readOnly: service.read_only ?? false,
            useInit: false,
            initImage: nil
        )

        var resource = ContainerConfiguration.Resources()
        let cpuCount: Int =
            service.deploy?.resources?.limits?.cpus.map({ Int($0) ?? 4 }) ?? 4
        let memoryInBytes =
            try service.deploy?.resources?.limits?.memory.map({
                try Parser.memoryStringAsMiB($0).mib()
            }) ?? 1024.mib()

        resource.cpus = cpuCount
        resource.memoryInBytes = memoryInBytes

        // arguments are passed in following management.entry point,
        // ie: as commands overrides the default command declared by the container image
        // https://docs.docker.com/reference/compose-file/services/#command
        let arguments: [String] = service.command ?? []

        var resolvedResult: [ContainerSnapshot] = []
        var failures: [String] = []

        messageStreamContinuation?.yield("Creating containers for \(serviceName)...")

        await withTaskGroup(
            of: (container: ContainerSnapshot?, error: String?).self
        ) { [baseManagement, resource] group in
            for containerName in containerNames {
                group.addTask {
                    do {
                        if let existing = try await shouldCreateContainer(
                            containerName,
                            shouldRecreate: recreateContainer
                        ) {
                            return (existing, nil)
                        }

                        var management = baseManagement
                        management.name = containerName

                        let container =
                            try await ContainerService.createContainer(
                                imageReference: image,
                                arguments: arguments,
                                process: process,
                                management: management,
                                resource: resource,
                                messageStreamContinuation: nil
                            )
                        return (container, nil)
                    } catch (let error) {
                        return (nil, "\(containerName): \(error)")
                    }
                }
            }

            for await result in group {
                if let container = result.container {
                    resolvedResult.append(container)
                    continue
                }
                if let error = result.error {
                    failures.append(error)
                }
            }

        }

        if !failures.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Error getting/creating containers: \n\(failures.joined(separator: "\n"))"
            )
        }

        return resolvedResult
    }

    static func shouldCreateContainer(_ name: String, shouldRecreate: Bool)
        async throws -> ContainerSnapshot?
    {
        guard shouldRecreate == false else {
            // should recreate. delete existing if there is any
            try? await ContainerService.deleteContainers(
                [name],
                force: true,
                messageStreamContinuation: nil
            )
            return nil
        }
        do {
            return try await ContainerService.getContainer(name)
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

    // <name>[,mac=XX:XX:XX:XX:XX:XX][,mtu=VALUE]
    // ex: default,mac=02:42:ac:11:00:02
    private static func resolveContainerNetworks(
        service: Service,
        networks: [String: DockerComposeParser.Network],
        shouldRebuild: Bool,
    ) async throws -> [String] {
        guard let serviceNetworks = service.networks else {
            return []
        }

        let strings: [String] = serviceNetworks.compactMap {
            (networkName, network) in
            var final = networks[networkName]?.name ?? networkName
            if let mac = network?.mac_address {
                final = "\(final), mac=\(mac)"
            }
            if let mtu = networks[networkName]?.mtu {
                final = "\(final), mtu=\(mtu)"
            }
            return final
        }

        let networkToBuild = networks.filter({ topLevel in
            serviceNetworks.keys.contains(topLevel.key)
                && topLevel.value.external != false
        }).map({ ($0.key, $0.value) })

        let result = await buildNetworks(
            networkToBuild,
            shouldRebuild: shouldRebuild,
            messageStreamContinuation: nil
        )

        if result.failedResource.count > 0 {
            throw ContainerizationError(
                .internalError,
                message:
                    "Error create networks. \n\(result.failedResource.joined(separator: "\n"))"
            )
        }

        return strings
    }

    // get or create volumes used by the service
    private static func resolveServiceVolumes(
        _ service: Service,
        shouldRebuild: Bool,
        topLevelVolume: [String: DockerComposeParser.Volume]
    ) async throws -> [Filesystem] {
        guard let volumes = service.volumes else {
            return []
        }

        var resolvedResult: [Filesystem] = []
        var failures: [String] = []

        await withTaskGroup(of: (fs: Filesystem?, error: String?).self) {
            group in
            for volume in volumes {
                group.addTask { [volume] in
                    do {
                        switch volume.type {
                        case .volume:
                            let namedVolume:
                                (String, DockerComposeParser.Volume)? =
                                    topLevelVolume.first(
                                        where: {
                                            $0.0 == volume.source
                                        })
                            let volumeConfiguration: VolumeConfiguration
                            if let namedVolume {
                                volumeConfiguration =
                                    try await ComposeService.buildVolume(
                                        namedVolume.1,
                                        shouldRebuild: shouldRebuild,
                                        volumeName: namedVolume.0
                                    )
                            } else {
                                // for those that are not defined in the top-level volumes key (source is nil),
                                // for example, the source is just a path on the host for a bind mount, a Docker image reference for an image mount,
                                // create an anonymous volume
                                let anonymousName =
                                    VolumeStorage.generateAnonymousVolumeName()

                                volumeConfiguration =
                                    try await VolumeService.createVolume(
                                        name: anonymousName,
                                        driver: "local",
                                        labels: [
                                            VolumeConfiguration.anonymousLabel:
                                                ""
                                        ],
                                        options: [:],
                                        size: nil,
                                        messageStreamContinuation: nil
                                    )
                            }
                            let fs = Filesystem.volume(
                                name: volumeConfiguration.name,
                                format: volumeConfiguration.format,
                                source: volumeConfiguration.source,
                                destination: volume.target,
                                options: (volume.read_only == true)
                                    ? ["ro"] : []
                            )
                            return (fs, nil)
                        case .bind:
                            var bindOptions: [String] = []
                            if let bind = volume.bind {
                                if let propagation = bind.propagation {
                                    bindOptions.append(
                                        "propagation=\(propagation)"
                                    )
                                }
                                if let create_host_path = bind.create_host_path
                                {
                                    bindOptions.append(
                                        "create_host_path=\(create_host_path)"
                                    )
                                }
                                if let selinux = bind.selinux {
                                    bindOptions.append("selinux=\(selinux)")
                                }
                            }

                            // analogous to container mount
                            let fs = Filesystem.virtiofs(
                                source: volume.source ?? volume.target,
                                destination: volume.target,
                                options: bindOptions
                                    + ((volume.read_only == true)
                                        ? ["ro"] : [])
                            )
                            return (fs, nil)
                        case .tmpfs:
                            var tmpfsOptions: [String] = []
                            if let tmpfs = volume.tmpfs {
                                if let mode = tmpfs.mode {
                                    tmpfsOptions.append("mode=\(mode)")
                                }
                                if let size = tmpfs.size {
                                    tmpfsOptions.append("size=\(size)")
                                }
                            }

                            let fs = Filesystem.tmpfs(
                                destination: volume.target,
                                options: tmpfsOptions
                                    + ((volume.read_only == true)
                                        ? ["ro"] : [])
                            )
                            return (fs, nil)
                        case .npipe:
                            return (nil, nil)
                        case .cluster:
                            return (nil, nil)
                        }

                    } catch (let error) {
                        return (
                            nil,
                            "\(volume.source ?? volume.target): \(error)"
                        )
                    }
                }

                for await result in group {
                    if let fs = result.fs {
                        resolvedResult.append(fs)
                        continue
                    }
                    if let error = result.error {
                        failures.append(error)
                    }
                }
            }
        }

        if !failures.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Error getting/creating volumes: \n\(failures.joined(separator: "\n"))"
            )
        }

        return resolvedResult
    }

    private static func resolveServiceTmpfs(_ service: Service) -> [Filesystem]
    {
        guard let tmpfs = service.tmpfs else {
            return []
        }
        return tmpfs.map({
            Filesystem.tmpfs(
                destination: $0.path,
                options: $0.options?.removeNilValue().compactMap({
                    AdditionalUtility.keyValueString(
                        key: $0.key,
                        value: $0.value
                    )
                }) ?? []
            )
        })
    }
}
