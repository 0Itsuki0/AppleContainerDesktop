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
import ContainerizationExtras
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
    @discardableResult
    static func startContainer(
        _ container: ContainerSnapshot,
        attachContainerStdout: Bool,
        attachContainerStdIn: Bool,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws -> Int32? {
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
            return nil
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
            let io = try ContainerAPIClient.ProcessIO.create(
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
                return nil
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

        if ArgumentParser.ExitCode(exitCode) == .failure {
            throw ArgumentParser.ExitCode(exitCode)
        }
        return exitCode
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
                        if error.isResourceNotFound {
                            return nil
                        }
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
                        if error.isResourceNotFound {
                            return nil
                        }
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

    // assume container is already started with startContainer above
    static func executeCommand(
        on containerId: ContainerSnapshotID,
        arguments: [String],
        processFlags: ContainerProcess,
        detach: Bool,
        onStdout: (@Sendable (String) -> Void)?,
        onStderr: (@Sendable (String) -> Void)?
    ) async throws -> Int32? {
        var exitCode: Int32 = 127
        let client = ContainerClient()
        let container = try await self.getContainer(containerId)
        if container.status != .running {
            throw ContainerizationError(
                .invalidState,
                message: "container \(container.id) is not running"
            )
        }

        let stdin = processFlags.interactive
        let tty = processFlags.tty

        guard let executable = arguments.first else {
            throw ContainerizationError(
                .invalidArgument,
                message: "no command specified for exec"
            )
        }

        var config = container.configuration.initProcess
        config.executable = executable
        config.arguments = [String](arguments.dropFirst())
        config.terminal = tty
        config.environment.append(
            contentsOf: try Parser.allEnv(
                imageEnvs: [],
                envFiles: processFlags.envFile,
                envs: processFlags.environments
            )
        )

        if let cwd = processFlags.workingDirectory {
            config.workingDirectory = cwd
        }

        let defaultUser = config.user
        let (user, additionalGroups) = Parser.user(
            user: processFlags.user,
            uid: processFlags.uid,
            gid: processFlags.gid,
            defaultUser: defaultUser
        )
        config.user = user
        config.supplementalGroups.append(contentsOf: additionalGroups)
        do {

            let io = try CustomProcessIO.create(
                tty: tty,
                interactive: stdin,
                detach: detach,
                onStdout: { onStdout?($0) },
                onStderr: { onStderr?($0) }
            )

            let process = try await client.createProcess(
                containerId: container.id,
                processId: UUID().uuidString.lowercased(),
                configuration: config,
                stdio: io.stdio
            )

            if detach {
                try await process.start()
                try io.closeAfterStart()
                return nil
            }

            if !processFlags.tty {
                var handler = SignalThreshold(
                    threshold: 3,
                    signals: [SIGINT, SIGTERM]
                )
                handler.start {
                    Darwin.exit(1)
                }
            }

            exitCode = try await io.handleProcess(
                process: process,
            )
        } catch {
            if error is ContainerizationError {
                throw error
            }
            throw ContainerizationError(
                .internalError,
                message: "failed to exec process \(error)"
            )
        }

        if ArgumentParser.ExitCode(exitCode) == .failure {
            throw ArgumentParser.ExitCode(exitCode)
        }
        return exitCode
    }
}

nonisolated struct CustomProcessIO: Sendable {
    let stdin: Pipe?
    let stdout: Pipe?
    let stderr: Pipe?

    static let signalSet: [Int32] = [
        SIGTERM,
        SIGINT,
        SIGUSR1,
        SIGUSR2,
        SIGWINCH,
    ]

    public let stdio: [FileHandle?]

    //    public let console: Terminal?

    public static func create(
        tty: Bool,
        interactive: Bool,
        detach: Bool,
        onStdout: @escaping (@Sendable (String) -> Void),
        onStderr: @escaping (@Sendable (String) -> Void)
    ) throws -> CustomProcessIO {

        var stdio = [FileHandle?](repeating: nil, count: 3)

        let stdin: Pipe? = {
            if !interactive {
                return nil
            }
            return Pipe()
        }()

        if let stdin {
            let pin = FileHandle.standardInput
            let stdinOSFile = OSFile(fd: pin.fileDescriptor)
            let pipeOSFile = OSFile(
                fd: stdin.fileHandleForWriting.fileDescriptor
            )
            try stdinOSFile.makeNonBlocking()
            nonisolated(unsafe) let buf = UnsafeMutableBufferPointer<UInt8>
                .allocate(capacity: Int(getpagesize()))

            pin.readabilityHandler = { handle in
                Self.streamStdin(
                    from: stdinOSFile,
                    to: pipeOSFile,
                    buffer: buf,
                ) {
                    pin.readabilityHandler = nil
                    buf.deallocate()
                    try? stdin.fileHandleForWriting.close()
                }
            }
            stdio[0] = stdin.fileHandleForReading
        }

        let stdout: Pipe? = {
            if detach {
                return nil
            }
            return Pipe()
        }()

        if let stdout {
            stdio[1] = stdout.fileHandleForWriting
            let rout = stdout.fileHandleForReading
            rout.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    rout.readabilityHandler = nil
                    return
                }
                if let string = String(data: data, encoding: .utf8) {
                    onStdout(string)
                }
            }
        }

        let stderr: Pipe? = {
            if detach || tty {
                return nil
            }
            return Pipe()
        }()
        if let stderr {
            let rerr = stderr.fileHandleForReading
            rerr.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    rerr.readabilityHandler = nil
                    return
                }
                if let string = String(data: data, encoding: .utf8) {
                    onStderr(string)
                }
            }
            stdio[2] = stderr.fileHandleForWriting
        }

        return .init(
            stdin: stdin,
            stdout: stdout,
            stderr: stderr,
            stdio: stdio,
        )
    }

    public func handleProcess(process: ClientProcess) async throws -> Int32 {
        let signals = AsyncSignalHandler.create(notify: Self.signalSet)
        return try await withThrowingTaskGroup(
            of: Int32?.self,
            returning: Int32.self
        ) { group in
            try await process.start()
            try closeAfterStart()

            let waitAdded = group.addTaskUnlessCancelled {
                let code = try await process.wait()
                return code
            }

            guard waitAdded else {
                group.cancelAll()
                return -1
            }

            _ = group.addTaskUnlessCancelled {
                for await sig in signals.signals {
                    do {
                        try await process.kill(sig)
                    } catch {
                        print(
                            """
                            failed to send signal
                             - "signal": "\(sig)",
                             - "error": "\(error)",
                            """
                        )
                    }
                }
                return nil
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

    public func closeAfterStart() throws {
        try stdin?.fileHandleForReading.close()
        try stdout?.fileHandleForWriting.close()
        try stderr?.fileHandleForWriting.close()
    }

    static func streamStdin(
        from: OSFile,
        to: OSFile,
        buffer: UnsafeMutableBufferPointer<UInt8>,
        onErrorOrEOF: () -> Void,
    ) {
        while true {
            let (bytesRead, action) = from.read(buffer)
            if bytesRead > 0 {
                let view = UnsafeMutableBufferPointer(
                    start: buffer.baseAddress,
                    count: bytesRead
                )

                let (bytesWritten, _) = to.write(view)
                if bytesWritten != bytesRead {
                    onErrorOrEOF()
                    return
                }
            }

            switch action {
            case .error(_), .eof, .brokenPipe:
                onErrorOrEOF()
                return
            case .again:
                return
            case .success:
                break
            }
        }
    }
}

nonisolated
    public struct OSFile: Sendable
{
    private let fd: Int32

    public enum IOAction: Equatable {
        case eof
        case again
        case success
        case brokenPipe
        case error(_ errno: Int32)
    }

    public init(fd: Int32) {
        self.fd = fd
    }

    public init(handle: FileHandle) {
        self.fd = handle.fileDescriptor
    }

    func makeNonBlocking() throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1 else {
            throw POSIXError.fromErrno()
        }

        if fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw POSIXError.fromErrno()
        }
    }

    func write(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> (
        wrote: Int, action: IOAction
    ) {
        if buffer.count == 0 {
            return (0, .success)
        }

        var bytesWrote: Int = 0
        while true {
            let n = Darwin.write(
                self.fd,
                buffer.baseAddress!.advanced(by: bytesWrote),
                buffer.count - bytesWrote
            )
            if n == -1 {
                if errno == EAGAIN || errno == EIO {
                    return (bytesWrote, .again)
                }
                return (bytesWrote, .error(errno))
            }

            if n == 0 {
                return (bytesWrote, .brokenPipe)
            }

            bytesWrote += n
            if bytesWrote < buffer.count {
                continue
            }
            return (bytesWrote, .success)
        }
    }

    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> (
        read: Int, action: IOAction
    ) {
        if buffer.count == 0 {
            return (0, .success)
        }

        var bytesRead: Int = 0
        while true {
            let n = Darwin.read(
                self.fd,
                buffer.baseAddress!.advanced(by: bytesRead),
                buffer.count - bytesRead
            )
            if n == -1 {
                if errno == EAGAIN || errno == EIO {
                    return (bytesRead, .again)
                }
                return (bytesRead, .error(errno))
            }

            if n == 0 {
                return (bytesRead, .eof)
            }

            bytesRead += n
            if bytesRead < buffer.count {
                continue
            }
            return (bytesRead, .success)
        }
    }
}
