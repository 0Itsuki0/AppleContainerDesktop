//
//  Utility.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import Foundation

import ContainerNetworkService
import ContainerPersistence
import Containerization
import ContainerizationError
internal import ContainerizationOCI
import TerminalProgress
import ContainerClient
import ContainerizationOS


struct Utility {
    static let signalSet: [Int32] = [
        SIGTERM,
        SIGINT,
        SIGUSR1,
        SIGUSR2,
        SIGWINCH,
    ]
    
    private static let infraImages = [
        DefaultsStore.get(key: .defaultBuilderImage),
        DefaultsStore.get(key: .defaultInitImage),
    ]
    
    nonisolated static func updateProgress(_ events: [ProgressUpdateEvent], messageStreamContinuation: AsyncStream<String>.Continuation?) {
        DispatchQueue.main.async {
            messageStreamContinuation?.yield(events.map(\.displayString).joined(separator: "\n"))
        }
    }
    
    static func isInfraImage(name: String) -> Bool {
       for infraImage in infraImages {
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
            throw ContainerizationError(.invalidArgument, message: "invalid entity name \(name)")
        }
    }

    static func createContainerConfig(
        imageReference: String,
        arguments: [String],
        process: ContainerProcess,
        management: ContainerManagement,
        resource: ContainerConfiguration.Resources,
        registryScheme: String,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> (ContainerConfiguration, Kernel) {
        let id = createContainerID(name: management.name)
        try validEntityName(id)

        var requestedPlatform = Parser.platform(os: management.os, arch: management.arch)
        if let platform = management.platform {
            requestedPlatform = try Parser.platform(from: platform)
        }
        let scheme = try RequestScheme(registryScheme)

        messageStreamContinuation?.yield("Fetching Image...")

        let image = try await ClientImage.fetch(
            reference: imageReference,
            platform: requestedPlatform,
            scheme: scheme,
            progressUpdate: { events in
                updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )

        // Unpack a fetched image before use
        messageStreamContinuation?.yield("Unpacking Image...")

        try await image.getCreateSnapshot(
            platform: requestedPlatform,
            progressUpdate: { events in
                updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )

            
        messageStreamContinuation?.yield("Fetching kernel...")

        let kernel = try await self.getKernel(management: management)

        // Pull and unpack the initial filesystem

        messageStreamContinuation?.yield("Fetching init image...")

        let initImage = try await ClientImage.fetch(
            reference: ClientImage.initImageRef, platform: .current, scheme: scheme,
            progressUpdate: { events in
                updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )

        messageStreamContinuation?.yield("Unpacking init image...")
        _ = try await initImage.getCreateSnapshot(
            platform: .current,
            progressUpdate: { events in
                updateProgress(events, messageStreamContinuation: messageStreamContinuation)
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

        var config = ContainerConfiguration(id: id, image: description, process: pc)
        config.platform = requestedPlatform

        config.resources = resource

        let resolvedMounts: [Filesystem] = management.virtualFileSystem + management.temporaryFileSystem + management.volumes

        config.mounts = resolvedMounts

        config.virtualization = management.virtualization

        config.networks = try getAttachmentConfigurations(containerId: config.id, networkIds: management.networks)
        for attachmentConfiguration in config.networks {
            let network: NetworkState = try await ClientNetwork.get(id: attachmentConfiguration.network)
            guard case .running(_, _) = network else {
                throw ContainerizationError(.invalidState, message: "network \(attachmentConfiguration.network) is not running")
            }
        }

        if management.dnsDisabled {
            config.dns = nil
        } else {
            let domain = management.dnsDomain ?? DefaultsStore.getOptional(key: .defaultDNSDomain)
            config.dns = .init(
                nameservers: management.dnsNameservers,
                domain: domain,
                searchDomains: management.dnsSearchDomains,
                options: management.dnsOptions
            )
        }

        if Platform.current.architecture == "arm64" && requestedPlatform.architecture == "amd64" {
            config.rosetta = true
        }

        config.labels = management.labels

        config.publishedPorts = management.publishPorts

        config.publishedSockets = management.publishSockets

        config.ssh = management.ssh

        return (config, kernel)
    }
     

    static func getAttachmentConfigurations(containerId: String, networkIds: [String]) throws -> [AttachmentConfiguration] {
        // make an FQDN for the first interface
        let fqdn: String?
        if !containerId.contains(".") {
            // add default domain if it exists, and container ID is unqualified
            if let dnsDomain = DefaultsStore.getOptional(key: .defaultDNSDomain) {
                fqdn = "\(containerId).\(dnsDomain)."
            } else {
                fqdn = nil
            }
        } else {
            // use container ID directly if fully qualified
            fqdn = "\(containerId)."
        }

        guard networkIds.isEmpty else {
            // networks may only be specified for macOS 26+
            guard #available(macOS 26, *) else {
                throw ContainerizationError(.invalidArgument, message: "non-default network configuration requires macOS 26 or newer")
            }

            // attach the first network using the fqdn, and the rest using just the container ID
            return networkIds.enumerated().map { item in
                guard item.offset == 0 else {
                    return AttachmentConfiguration(network: item.element, options: AttachmentOptions(hostname: containerId))
                }
                return AttachmentConfiguration(network: item.element, options: AttachmentOptions(hostname: fqdn ?? containerId))
            }
        }
        // if no networks specified, attach to the default network
        return [AttachmentConfiguration(network: ClientNetwork.defaultNetworkName, options: AttachmentOptions(hostname: fqdn ?? containerId))]
    }

    private static func getKernel(management: ContainerManagement) async throws -> Kernel {
        // For the image itself we'll take the user input and try with it as we can do userspace
        // emulation for x86, but for the kernel we need it to match the hosts architecture.
        let s: SystemPlatform = .current
        if let userKernel = management.kernel {
            guard FileManager.default.fileExists(atPath: userKernel) else {
                throw ContainerizationError(.notFound, message: "Kernel file not found at path \(userKernel)")
            }
            let p = URL(filePath: userKernel)
            return .init(path: p, platform: s)
        }
        return try await ClientKernel.getDefaultKernel(for: s)
    }


    static func handleProcess(io: ProcessIO, process: ClientProcess) async throws -> Int32 {
        let signals = AsyncSignalHandler.create(notify: signalSet)
        return try await withThrowingTaskGroup(of: Int32?.self, returning: Int32.self) { group in
            let waitAdded = group.addTaskUnlessCancelled {
                let code = try await process.wait()
                try await io.wait()
                return code
            }

            guard waitAdded else {
                group.cancelAll()
                return -1
            }

            try await process.start()
            try io.closeAfterStart()

            if let current = io.console {
                let size = try current.size
                // It's supremely possible the process could've exited already. We shouldn't treat
                // this as fatal.
                try? await process.resize(size)
                _ = group.addTaskUnlessCancelled {
                    let winchHandler = AsyncSignalHandler.create(notify: [SIGWINCH])
                    for await _ in winchHandler.signals {
                        do {
                            try await process.resize(try current.size)
                        } catch(let error) {
                            print("failed to send terminal resize event. \(error)")
                        }
                    }
                    return nil
                }
            } else {
                _ = group.addTaskUnlessCancelled {
                    for await sig in signals.signals {
                        do {
                            try await process.kill(sig)
                        } catch(let error) {
                            print("failed to send signal. signal: \(sig). Error: \(error)")
                        }
                    }
                    return nil
                }
            }

            while true {
                let result = try await group.next()
                if result == nil {
                    return -1
                }
                let status = result!
                if let status {
                    group.cancelAll()
                    return status
                }
            }
            return -1
        }
    }
    
    
    static func parseProcessConfiguration(
        arguments: [String],
        process: ContainerProcess,
        management: ContainerManagement,
        config: ContainerizationOCI.ImageConfig?
    ) throws -> ProcessConfiguration {

        let imageEnvVars = config?.env ?? []
        let envvars = try Parser.allEnv(imageEnvs: imageEnvVars, envFiles: process.envFile, envs: process.environments)

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
            throw ContainerizationError(.invalidArgument, message: "Command/Entrypoint not specified for container process")
        }

        let defaultUser: ProcessConfiguration.User = {
            if let u = config?.user {
                return .raw(userString: u)
            }
            return .id(uid: 0, gid: 0)
        }()

        let (user, additionalGroups) = Parser.user(
            user: process.user, uid: process.uid,
            gid: process.gid, defaultUser: defaultUser)

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
    
    
    // TODO: Use plugin loader
//    static func createPluginLoader() async throws -> PluginLoader {
//        let installRoot = CommandLine.executablePathUrl
//            .deletingLastPathComponent()
//            .appendingPathComponent("..")
//            .standardized
//        let pluginsURL = PluginLoader.userPluginsDir(installRoot: installRoot)
//        var directoryExists: ObjCBool = false
//        _ = FileManager.default.fileExists(atPath: pluginsURL.path, isDirectory: &directoryExists)
//        let userPluginsURL = directoryExists.boolValue ? pluginsURL : nil
//
//        // plugins built into the application installed as a macOS app bundle
//        let appBundlePluginsURL = Bundle.main.resourceURL?.appending(path: "plugins")
//
//        // plugins built into the application installed as a Unix-like application
//        let installRootPluginsURL =
//            installRoot
//            .appendingPathComponent("libexec")
//            .appendingPathComponent("container")
//            .appendingPathComponent("plugins")
//            .standardized
//
//        let pluginDirectories = [
//            userPluginsURL,
//            appBundlePluginsURL,
//            installRootPluginsURL,
//        ].compactMap { $0 }
//
//        let pluginFactories: [any PluginFactory] = [
//            DefaultPluginFactory(),
//            AppBundlePluginFactory(),
//        ]
//
//        guard let systemHealth = try? await ClientHealthCheck.ping(timeout: .seconds(10)) else {
//            throw ContainerizationError(.timeout, message: "unable to retrieve application data root from API server")
//        }
//        return try PluginLoader(
//            appRoot: systemHealth.appRoot,
//            installRoot: systemHealth.installRoot,
//            pluginDirectories: pluginDirectories,
//            pluginFactories: pluginFactories,
//            log: nil
//        )
//    }

}
