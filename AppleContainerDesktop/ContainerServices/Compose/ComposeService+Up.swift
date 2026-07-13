//
//  ComposeService+Up.swift
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
    ) async throws -> [ContainerSnapshot] {
        let projectDirectory =
            projectDirectory ?? baseCompose.deletingLastPathComponent()

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
            compose: compose,
            nameOverride: nameOverride
        )

        messageStreamContinuation?.yield(
            "Building compose: \(projectName)..."
        )

        let selectedServices = selectServices(
            compose: compose,
            requestedServices: requestedServices,
            requestedProfiles: requestedProfiles,
        )

        messageStreamContinuation?.yield(
            "Building \(selectedServices.count) services..."
        )

        let networks = compose.networks?.mapValues({$0 ?? Network()}) ?? [:]
        let volumes = compose.volumes?.mapValues({$0 ?? Volume()}) ?? [:]
        let secrets = compose.secrets?.mapValues({$0 ?? Secret()}) ?? [:]

        var containersBuilt: [ContainerSnapshot] = []

        try await withThrowingTaskGroup(of: [ContainerSnapshot].self) { group in
            for (serviceName, service) in selectedServices {
                group.addTask {
                    return try await resolveServiceContainers(
                        service,
                        serviceName: serviceName,
                        networks: networks,
                        volumes: volumes,
                        secrets: secrets,
                        projectName: projectName,
                        rebuildImage: forceRebuild,
                        rebuildOtherResource: forceRecreate
                    )
                }
            }

            for try await result in group {
                containersBuilt.append(contentsOf: result)
            }
        }

        messageStreamContinuation?.yield(
            "Finish building \(containersBuilt.count) containers..."
        )

        // TODO: - nest start service (containers) in order based on the depends_on field

        return containersBuilt
    }

    func startServices() async throws {

    }

    // get or create container
    static func resolveServiceContainers(
        _ service: Service,
        serviceName: String,
        networks: [String: Network],
        volumes: [String: Volume],
        secrets: [String: Secret],
        projectName: String,
        rebuildImage: Bool,
        rebuildOtherResource: Bool
    ) async throws -> [ContainerSnapshot] {

        let count = service.deploy?.replicas ?? 1
        // Compose does not scale a service beyond one container if the Compose file specifies a container_name. Attempting to do so results in an error.
        let container_name = service.container_name
        if let container_name, count > 1 {
            throw ContainerizationError(
                .invalidArgument,
                message: "Container with explicit name cannot be scaled."
            )
        }

        let image: String
        if service.build != nil {
            // docker
            let clientImage = try await buildService(
                service,
                serviceName: serviceName,
                shouldRebuild: rebuildImage,
                secrets: secrets
            )
            image = clientImage.reference
        } else if let serviceImage = service.image {
            // remote
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
                index: index
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
            volumes: try await service.resolveVolumes(
                shouldRebuild: rebuildOtherResource,
                topLevelVolume: volumes
            ),
            publishPorts: service.ports?.map(\.publishPort).removeNilValue()
                ?? [],
            publishSockets: [],
            temporaryFileSystem: service.resolveTmpfs(),
            // NOTE: name to be update for each contianer
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

        await withTaskGroup(
            of: (container: ContainerSnapshot?, error: String?).self
        ) { [baseManagement, resource] group in
            for containerName in containerNames {
                group.addTask {
                    do {
                        if let existing = try await shouldCreateContainer(
                            containerName,
                            shouldRecreate: rebuildImage  // container is based on image
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

    static func containerName(
        explicit: String?,
        projectName: String,
        serviceName: String,
        index: Int
    ) -> String {
        if let explicit {
            return explicit
        }
        return "\(projectName)_\(serviceName)_\(index)"
    }

    // <name>[,mac=XX:XX:XX:XX:XX:XX][,mtu=VALUE]
    // ex: default,mac=02:42:ac:11:00:02
    static func resolveContainerNetworks(
        service: Service,
        networks: [String: Network],
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

}

extension Network {
    var mtu: String? {
        return self.driver_opts?["com.docker.network.driver.mtu"] ?? nil
    }

}

extension Service.Platform {
    var containerPlatform: ContainerizationOCI.Platform {
        Platform(
            arch: self.arch ?? "",
            os: self.os,
            variant: self.variant
        )
    }
}

extension Service {
    // The network with the highest gw_priority is selected as the default gateway for the service container.
    // If unspecified, the default value is 0.
    var defaultNetwork: (String, Network?)? {
        guard let networks = self.networks else {
            return nil
        }
        let sorted = networks.map({ ($0.key, $0.value) }).sorted(by: {
            ($0.1?.gw_priority ?? 0) > ($1.1?.gw_priority ?? 0)
        })
        return sorted.first
    }

    var virtualization: Bool {
        guard
            let device = self.deploy?.resources?.reservations?.devices?.first(
                where: { $0.options?["virtualization"] != nil })
        else {
            return false
        }

        guard let virtualization = device.options?["virtualization"],
            let virtualization
        else {
            return false
        }

        return Bool(virtualization) ?? false
    }

    // get or create volumes used by the service
    func resolveVolumes(
        shouldRebuild: Bool,
        topLevelVolume: [String: DockerComposeParser.Volume]
    ) async throws -> [Filesystem] {
        guard let volumes = self.volumes else {
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

    func resolveTmpfs() -> [Filesystem] {
        guard let tmpfs = self.tmpfs else {
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

extension VolumeConfiguration {
    //    var fileSystemVolume: Filesystem {
    //        return Filesystem.volume(
    //            name: self.name,
    //            format: self.format,
    //            source: self.source,
    //            destination: self.destination,
    //            options: self.options
    //        )
    //    }
}
extension Service.Volume {
    func resolve(topLevelVolumes: [VolumeConfiguration]) -> [Filesystem] {

        return []
    }
}

extension Service.Port {
    var publishPort: PublishPort? {
        // published: Host port or range, e.g. "8080" or "8080-8090". Nil = Docker picks a random host port.
        guard let parsedPort = self.parsedPort else { return nil }
        guard let ipV4 = try? IPv4Address(self.host_ip ?? "0.0.0.0") else {
            return nil
        }

        // HOST is [IP:](port | range) (optional). If it is not set, it binds to all network interfaces (0.0.0.0).
        // PROTOCOL restricts ports to a specified protocol either tcp or udp(optional). Default is tcp.
        return try? PublishPort(
            hostAddress: IPAddress.v4(ipV4),
            hostPort: parsedPort.hostPort,
            containerPort: parsedPort.containerPort,
            proto: self.protocol?.publishProtocol ?? .tcp,
            count: parsedPort.count
        )

    }

    var parsedPort: (hostPort: UInt16, containerPort: UInt16, count: UInt16)? {
        func parseRange(_ s: String) -> (UInt16, UInt16)? {
            if let dash = s.firstIndex(of: "-") {
                guard let start = UInt16(s[s.startIndex..<dash]),
                    let end = UInt16(s[s.index(after: dash)...]),
                    end >= start
                else { return nil }
                return (start, UInt16(end - start + 1))
            } else {
                guard let p = UInt16(s) else { return nil }
                return (p, 1)
            }
        }

        guard let (containerPort, containerCount) = parseRange(target) else {
            return nil
        }

        guard let published = published else {
            // No published port specified — Docker assigns a random host port.
            return (0, containerPort, containerCount)
        }

        guard let (hostPort, hostCount) = parseRange(published),
            hostCount == containerCount
        else { return nil }

        return (hostPort, containerPort, hostCount)
    }
}

extension Service.PortProtocol {
    var publishProtocol: PublishProtocol {
        switch self {
        case .tcp:
            return .tcp
        case .udp:
            return .udp
        }
    }
}
