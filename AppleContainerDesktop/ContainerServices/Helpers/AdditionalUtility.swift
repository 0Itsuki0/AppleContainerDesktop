//
//  Utility.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationExtras
internal import ContainerizationOCI
import ContainerizationOS
import Foundation
import TerminalProgress

enum AdditionalUtility {
    static let signalSet: [Int32] = [
        SIGTERM,
        SIGINT,
        SIGUSR1,
        SIGUSR2,
        SIGWINCH,
    ]

    nonisolated static func updateProgress(
        _ events: [ProgressUpdateEvent],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) {
        DispatchQueue.main.async {
            messageStreamContinuation?.yield(
                events.map(\.displayString).joined(separator: "\n")
            )
        }
    }

    public static func isInfraImage(
        name: String,
        builderImage: String,
        initImage: String
    ) -> Bool {
        for infraImage in [builderImage, initImage] {
            if name == infraImage {
                return true
            }
        }
        return false
    }

    static func createContainerID(name: String?) -> String {
        guard let name, !name.isEmpty else {
            return UUID().uuidString.lowercased()
        }
        return name
    }

    static func validEntityName(_ name: String) throws {
        let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9_.-]+$"#
        let regex = try Regex(pattern)
        if try regex.firstMatch(in: name) == nil {
            throw ContainerizationError(
                .invalidArgument,
                message: "invalid entity name \(name)"
            )
        }
    }

    static func createContainerConfig(
        id: String,
        imageReference: String,
        arguments: [String],
        process: ContainerProcess,
        management: ContainerManagement,
        resource: ContainerConfiguration.Resources,
        registryScheme: String,
        containerSystemConfig: ContainerSystemConfig,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> (ContainerConfiguration, Kernel, String?) {
        let requestedPlatform = try DefaultPlatform.resolveWithDefaults(
            platform: management.platform,
            os: management.os,
            arch: management.arch,
            log: nil
        )
        let scheme = try RequestScheme(registryScheme)

        messageStreamContinuation?.yield("Fetching Image...")

        let image = try await ClientImage.fetch(
            reference: imageReference,
            platform: requestedPlatform,
            scheme: scheme,
            containerSystemConfig: containerSystemConfig,
            progressUpdate: { events in
                updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        // Unpack a fetched image before use
        messageStreamContinuation?.yield("Unpacking Image...")

        try await image.getCreateSnapshot(
            platform: requestedPlatform,
            progressUpdate: { events in
                updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        messageStreamContinuation?.yield("Fetching kernel...")

        let kernel = try await self.getKernel(management: management)

        // Pull and unpack the initial filesystem

        messageStreamContinuation?.yield("Fetching init image...")
        let initImageRef = management.initImage ?? containerSystemConfig.vminit.image
        let initImage = try await ClientImage.fetch(
            reference: initImageRef,
            platform: .current,
            scheme: scheme,
            containerSystemConfig: containerSystemConfig,
            progressUpdate: { events in
                updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        messageStreamContinuation?.yield("Unpacking init image...")
        _ = try await initImage.getCreateSnapshot(
            platform: .current,
            progressUpdate: { events in
                updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )

        let imageConfig = try await image.config(for: requestedPlatform).config
        let description = image.description
        let pc = try parseProcessConfiguration(
            arguments: arguments,
            process: process,
            management: management,
            config: imageConfig
        )

        var config = ContainerConfiguration(
            id: id,
            image: description,
            process: pc
        )
        config.platform = requestedPlatform

        config.resources = resource

        let resolvedMounts: [Filesystem] =
            management.virtualFileSystem + management.temporaryFileSystem
            + management.volumes

        config.mounts = resolvedMounts

        config.virtualization = management.virtualization

        let parsedNetworks = try management.networks.map {
            try Parser.network($0)
        }
        if management.networks.contains(NetworkClient.noNetworkName) {
            guard management.networks.count == 1 else {
                throw ContainerizationError(
                    .unsupported,
                    message:
                        "no other networks may be created along with network \(NetworkClient.noNetworkName)"
                )
            }
            config.networks = []
        } else {
            let networkClient = NetworkClient()
            let builtinNetworkId = try await networkClient.builtin?.id
            config.networks = try getAttachmentConfigurations(
                containerId: config.id,
                builtinNetworkId: builtinNetworkId,
                networks: parsedNetworks,
                dnsDomain: containerSystemConfig.dns.domain,
            )
            for attachmentConfiguration in config.networks {
                _ = try await networkClient.get(
                    id: attachmentConfiguration.network
                )
            }
        }

        if management.dnsDisabled {
            config.dns = nil
        } else {
            let domain = management.dnsDomain ?? containerSystemConfig.dns.domain
            config.dns = .init(
                nameservers: management.dnsNameservers,
                domain: domain,
                searchDomains: management.dnsSearchDomains,
                options: management.dnsOptions
            )
        }

        if Platform.current.architecture == "arm64"
            && requestedPlatform.architecture == "amd64"
        {
            config.rosetta = true
        }

        config.labels = management.labels

        config.publishedPorts = management.publishPorts

        config.publishedSockets = management.publishSockets

        config.ssh = management.ssh
        config.readOnly = management.readOnly
        config.useInit = management.useInit

        return (config, kernel, management.initImage)
    }

    static func getAttachmentConfigurations(
        containerId: String,
        builtinNetworkId: String?,
        networks: [Parser.ParsedNetwork],
        dnsDomain: String?,
    ) throws -> [AttachmentConfiguration] {
        // Validate MAC addresses if provided
        for network in networks {
            if let mac = network.macAddress {
                try ContainerAPIClient.Utility.validMACAddress(mac)
            }
        }

        // make an FQDN for the first interface
        let fqdn: String?
        if !containerId.contains(".") {
            // add default domain if it exists, and container ID is unqualified
            if let dnsDomain {
                fqdn = "\(containerId).\(dnsDomain)."
            } else {
                fqdn = nil
            }
        } else {
            // use container ID directly if fully qualified
            fqdn = "\(containerId)."
        }

        guard networks.isEmpty else {
            // Check if this is only the default network with properties (e.g., MAC address)
            let isOnlyDefaultNetwork =
                networks.count == 1 && networks[0].name == builtinNetworkId

            // networks may only be specified for macOS 26+ (except for default network with properties)
            if !isOnlyDefaultNetwork {
                guard #available(macOS 26, *) else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message:
                            "non-default network configuration requires macOS 26 or newer"
                    )
                }
            }

            // attach the first network using the fqdn, and the rest using just the container ID
            return try networks.enumerated().map { item in
                let macAddress = try item.element.macAddress.map {
                    try MACAddress($0)
                }
                let mtu = item.element.mtu ?? 1280
                guard item.offset == 0 else {
                    return AttachmentConfiguration(
                        network: item.element.name,
                        options: AttachmentOptions(
                            hostname: containerId,
                            macAddress: macAddress,
                            mtu: mtu
                        )
                    )
                }
                return AttachmentConfiguration(
                    network: item.element.name,
                    options: AttachmentOptions(
                        hostname: fqdn ?? containerId,
                        macAddress: macAddress,
                        mtu: mtu
                    )
                )
            }
        }

        // if no networks specified, attach to the default network
        guard let builtinNetworkId else {
            throw ContainerizationError(
                .invalidState,
                message: "builtin network is not present"
            )
        }
        return [
            AttachmentConfiguration(
                network: builtinNetworkId,
                options: AttachmentOptions(
                    hostname: fqdn ?? containerId,
                    macAddress: nil,
                    mtu: 1280
                )
            )
        ]
    }

    private static func getKernel(management: ContainerManagement) async throws
        -> Kernel
    {
        // For the image itself we'll take the user input and try with it as we can do userspace
        // emulation for x86, but for the kernel we need it to match the hosts architecture.
        let s: SystemPlatform = .current
        if let userKernel = management.kernel {
            guard FileManager.default.fileExists(atPath: userKernel) else {
                throw ContainerizationError(
                    .notFound,
                    message: "Kernel file not found at path \(userKernel)"
                )
            }
            let p = URL(filePath: userKernel)
            return .init(path: p, platform: s)
        }
        return try await ClientKernel.getDefaultKernel(for: s)
    }

    static func parseProcessConfiguration(
        arguments: [String],
        process: ContainerProcess,
        management: ContainerManagement,
        config: ContainerizationOCI.ImageConfig?
    ) throws -> ProcessConfiguration {

        let imageEnvVars = config?.env ?? []
        let envvars = try Parser.allEnv(
            imageEnvs: imageEnvVars,
            envFiles: process.envFile,
            envs: process.environments
        )

        let workingDir: String = {
            if let cwd = process.workingDirectory {
                return cwd
            }
            if let cwd = config?.workingDir {
                return cwd
            }
            return "/"
        }()

        let processArguments: [String]? = {
            var result: [String] = []
            var hasEntrypointOverride: Bool = false
            // ensure the entrypoint is honored if it has been explicitly set by the user
            if let entrypoint = management.entryPoint, !entrypoint.isEmpty {
                result = [entrypoint]
                hasEntrypointOverride = true
            } else if let entrypoint = config?.entrypoint, !entrypoint.isEmpty {
                result = entrypoint
            }
            if !arguments.isEmpty {
                result.append(contentsOf: arguments)
            } else {
                if let cmd = config?.cmd, !hasEntrypointOverride, !cmd.isEmpty {
                    result.append(contentsOf: cmd)
                }
            }
            return result.count > 0 ? result : nil
        }()

        guard let commandToRun = processArguments, commandToRun.count > 0 else {
            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Command/Entrypoint not specified for container process"
            )
        }

        let defaultUser: ProcessConfiguration.User = {
            if let u = config?.user {
                return .raw(userString: u)
            }
            return .id(uid: 0, gid: 0)
        }()

        let (user, additionalGroups) = Parser.user(
            user: process.user,
            uid: process.uid,
            gid: process.gid,
            defaultUser: defaultUser
        )

        return .init(
            executable: commandToRun.first!,
            arguments: [String](commandToRun.dropFirst()),
            environment: envvars,
            workingDirectory: workingDir,
            terminal: process.tty,
            user: user,
            supplementalGroups: additionalGroups
        )
    }

    nonisolated
        static func keyValueString(key: String, value: String) -> String
    {
        return "\(key)=\(value)"
    }

}
