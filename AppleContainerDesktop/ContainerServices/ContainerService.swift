//
//  ContainerService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//

import ArgumentParser
import ContainerAPIClient
import ContainerCommands
import ContainerPersistence
import ContainerResource
import ContainerizationError
internal import ContainerizationOCI
import ContainerizationOS
import Foundation

enum ContainerService {

    @discardableResult
    static func createContainer(
        imageReference: String,
        // arguments are passed in following management.entry point,
        // ie: as commands overrides the default command declared by the container image
        // https://docs.docker.com/reference/compose-file/services/#command
        arguments: [String],
        process: ContainerProcess,
        management: ContainerManagement,
        resource: ContainerConfiguration.Resources,
        registryScheme: String = RequestScheme.auto.rawValue,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> ContainerSnapshot {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        let id = AdditionalUtility.createContainerID(name: management.name)
        try AdditionalUtility.validEntityName(id)

        messageStreamContinuation?.yield("Creating Container: \(id)...")

        let (configuration, kernel, initImage) =
            try await AdditionalUtility.createContainerConfig(
                id: id,
                imageReference: imageReference,
                arguments: arguments,
                process: process,
                management: management,
                resource: resource,
                registryScheme: registryScheme,
                containerSystemConfig: containerSystemConfig,
                messageStreamContinuation: messageStreamContinuation
            )

        let options = ContainerCreateOptions(autoRemove: management.remove)
        let client = ContainerClient()
        try await client.create(
            configuration: configuration,
            options: options,
            kernel: kernel,
            initImage: initImage
        )

        if !management.cidfile.isEmpty {
            let path = management.cidfile
            let data = id.data(using: .utf8)
            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o644
            let success = FileManager.default.createFile(
                atPath: path,
                contents: data,
                attributes: attributes
            )
            guard success else {
                throw ContainerizationError(
                    .internalError,
                    message: "failed to create cid file at \(path): \(errno)"
                )
            }
        }

        messageStreamContinuation?.yield("Container created: \(id)")
        return try await getContainer(id)
    }

    // attachContainerStdIn: true for interactive
    static func startContainer(
        _ container: ContainerSnapshot,
        attachContainerStdout: Bool,
        attachContainerStdIn: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let client = ContainerClient()

        messageStreamContinuation?.yield(
            "Starting Container: \(container.id)..."
        )

        var exitCode: Int32 = 127

        let detach = !attachContainerStdout && !attachContainerStdIn
        if container.status == .running {
            if !detach {
                throw ContainerizationError(
                    .invalidArgument,
                    message:
                        "attach is currently unsupported on already running containers"
                )
            }
            return
        }

        for mount in container.configuration.mounts where mount.isVirtiofs {
            if !FileManager.default.fileExists(atPath: mount.source) {
                throw ContainerizationError(
                    .invalidState,
                    message:
                        "mount source path '\(mount.source)' does not exist"
                )
            }
        }

        do {

            messageStreamContinuation?.yield("Initializing Process...")
            let io = try ProcessIO.create(
                tty: container.configuration.initProcess.terminal,
                interactive: attachContainerStdIn,
                detach: detach
            )
            defer {
                try? io.close()
            }

            messageStreamContinuation?.yield("Bootstrapping container...")
            var env: [String: String] = [:]
            if let sshAuthSock = ProcessInfo.processInfo.environment[
                "SSH_AUTH_SOCK"
            ] {
                env["SSH_AUTH_SOCK"] = sshAuthSock
            }

            let process = try await client.bootstrap(
                id: container.id,
                stdio: io.stdio,
                dynamicEnv: env
            )

            if detach {
                try await process.start()
                messageStreamContinuation?.yield("Process started...")
                try io.closeAfterStart()
                return
            }

            exitCode = try await io.handleProcess(
                process: process,
                log: ApplicationManager.logger
            )
        } catch (let error) {
            try? await client.stop(id: container.id)

            if error is ContainerizationError {
                throw error
            }

            throw ContainerizationError(
                .internalError,
                message: "failed to start container: \(error)"
            )
        }
        throw ArgumentParser.ExitCode(exitCode)
    }

    static func listContainers() async throws -> [ContainerSnapshot] {
        let client = ContainerClient()
        let filters = ContainerListFilters(status: nil).withoutMachines()
        let containers = try await client.list(filters: filters)
        return containers
    }

    static func getContainer(_ id: ContainerSnapshotID) async throws
        -> ContainerSnapshot
    {
        guard
            let item = try await listContainers().first(where: { id == $0.id })
        else {
            throw ContainerizationError(
                .notFound,
                message: "container not found: \(id)"
            )
        }
        return item
    }

    // boot: Boot log if true, otherwise, stdio
    static func getContainerLog(_ id: ContainerSnapshotID, boot: Bool)
        async throws -> String
    {
        let client = ContainerClient()
        let fileHandles = try await client.logs(id: id)

        let fileHandle = boot ? fileHandles[1] : fileHandles[0]

        // Fast path if all they want is the full file.
        guard let data = try fileHandle.readToEnd() else {
            return ""
        }
        guard let logs = String(data: data, encoding: .utf8) else {
            throw ContainerizationError(
                .internalError,
                message: "failed to convert container logs to utf8"
            )
        }

        return logs.trimmingCharacters(in: .newlines)
    }

    static func stopContainers(
        _ containers: [String],
        stopTimeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let client = ContainerClient()

        messageStreamContinuation?.yield(
            "Stopping \(containers.count) Container(s)..."
        )

        let stopOptions = ContainerStopOptions(
            timeoutInSeconds: stopTimeoutSeconds,
            signal: "SIGTERM"
        )

        var failed: [(String, Error)] = []
        await withTaskGroup(of: (String, Error)?.self) { group in
            for container in containers {
                group.addTask {
                    do {
                        try await client.stop(id: container, opts: stopOptions)
                        messageStreamContinuation?.yield(
                            "Stopped container: \(container)"
                        )
                        return nil
                    } catch (let error) {
                        messageStreamContinuation?.yield(
                            "failed to stop container \(container): \(error)"
                        )
                        return (container, error)
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

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message:
                    "Failed to stop one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }

    static func deleteContainers(
        _ containers: [ContainerSnapshotID],
        force: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let containers = try await self.listContainers().filter({
            containers.contains($0.id)
        })
        guard !containers.isEmpty else {
            return
        }
        try await self.deleteContainers(
            containers,
            force: force,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    static func deleteContainers(
        _ containers: [ContainerSnapshot],
        force: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let client = ContainerClient()

        messageStreamContinuation?.yield(
            "Deleting \(containers.count) Container(s)..."
        )

        var failed: [(String, Error)] = []
        await withTaskGroup(of: (String, Error)?.self) { group in
            for container in containers {
                group.addTask {
                    do {
                        if container.status == .running && !force {
                            throw ContainerizationError(
                                .invalidState,
                                message: "container: \(container.id) is running"
                            )
                        }

                        try await client.delete(id: container.id, force: force)
                        messageStreamContinuation?.yield(
                            "Container deleted: \(container.id)"
                        )
                        return nil
                    } catch (let error) {
                        messageStreamContinuation?.yield(
                            "failed to delete container \(container.id): \(error)"
                        )
                        return (container.id, error)
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
                    "Failed to delete one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"

            )
        }
    }
}
