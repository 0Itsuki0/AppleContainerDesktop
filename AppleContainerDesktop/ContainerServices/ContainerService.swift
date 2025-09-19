//
//  ContainerService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//


import Foundation

import ContainerClient
import ContainerizationError
internal import ContainerizationOCI
import ContainerizationOS
import ArgumentParser


class ContainerService {
    
    static func createContainer(
        imageReference: String,
        arguments: [KeyValueModel],
        process: ContainerProcess,
        management: ContainerManagement,
        resource: ContainerConfiguration.Resources,
        registryScheme: String = RequestScheme.auto.rawValue,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        let id = Utility.createContainerID(name: management.name)
        try Utility.validEntityName(id)

        let (configuration, kernel) = try await Utility.createContainerConfig(
            imageReference: imageReference,
            arguments: arguments.stringArray,
            process: process,
            management: management,
            resource: resource,
            registryScheme: registryScheme,
            messageStreamContinuation: messageStreamContinuation

        )

        let options = ContainerCreateOptions(autoRemove: management.remove)
        let container = try await ClientContainer.create(configuration: configuration, options: options, kernel: kernel)

        if !management.cidfile.isEmpty {
            let path = management.cidfile
            let data = container.id.data(using: .utf8)
            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o644
            let success = FileManager.default.createFile(
                atPath: path,
                contents: data,
                attributes: attributes
            )
            guard success else {
                throw ContainerizationError(
                    .internalError, message: "failed to create cid file at \(path): \(errno)")
            }
        }

        messageStreamContinuation?.yield("Container created: \(container.id)")
    }
   
        
    // attachContainerStdIn: true for interactive
    static func startContainer(_ container: ClientContainer, attachContainerStdout: Bool, attachContainerStdIn: Bool, messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {

        var exitCode: Int32 = 127

        do {
            let detach = !attachContainerStdout && !attachContainerStdIn
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
            let process = try await container.bootstrap(stdio: io.stdio)

            if detach {

                try await process.start()
                messageStreamContinuation?.yield("Process started...")
                try io.closeAfterStart()
                return
            }

            exitCode = try await Utility.handleProcess(io: io, process: process)
        } catch(let error) {            
            try? await container.stop()

            if error is ContainerizationError {
                throw error
            }
            
            throw ContainerizationError(.internalError, message: "failed to start container: \(error)")
        }
        throw ArgumentParser.ExitCode(exitCode)
    }

    
    static func listContainers() async throws -> [ClientContainer] {
        let containers = try await ClientContainer.list()
        return containers
    }
    
    static func getContainer(_ id: ClientContainerID) async throws -> ClientContainer {
        let container = try await ClientContainer.get(id: id)
        return container
    }
    
    
    // boot: Boot log if true, otherwise, stdio
    static func getContainerLog(_ id: ClientContainerID, boot: Bool) async throws -> String {
        let container = try await self.getContainer(id)
        let fileHandles = try await container.logs()
        
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
        containers: [ClientContainer],
        stopTimeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let signal = try Signals.parseSignal("SIGTERM")
        let stopOptions = ContainerStopOptions(
            timeoutInSeconds: stopTimeoutSeconds,
            signal: signal
        )

        var failed: [(String, Error)] = []
        try await withThrowingTaskGroup(of: (String, Error)?.self) { group in
            for container in containers {
                group.addTask {
                    do {
                        try await container.stop(opts: stopOptions)
                        messageStreamContinuation?.yield("Stopped container: \(container.id)")
                        return nil
                    } catch(let error) {
                        messageStreamContinuation?.yield("failed to stop container \(container.id): \(error)")
                        return (container.id, error)
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

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message: "Failed to stop one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }

    }
    
    static func deleteContainers(_ containers: [ClientContainer], force: Bool, messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {
        var failed: [(String, Error)] = []
        try await withThrowingTaskGroup(of: (String, Error)?.self) { group in
            for container in containers {
                group.addTask {
                    do {
                        if container.status == .running && !force {
                            throw ContainerizationError(.invalidState, message: "container: \(container.id) is running")
                        }

                        try await container.delete(force: force)
                        messageStreamContinuation?.yield("Container deleted: \(container.id)")
                        return nil
                    } catch(let error) {
                        messageStreamContinuation?.yield("failed to delete container \(container.id): \(error)")
                        return (container.id, error)
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
                message: "Failed to delete one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"

            )
        }
    }

}
