//
//  SystemService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import ContainerAPIClient
import ContainerCommands
import ContainerPersistence
import ContainerPlugin
import ContainerResource
internal import ContainerizationEXT4
import ContainerizationError
internal import ContainerizationOCI
import Foundation

class SystemService {

    static private let launchPrefix: String = "com.apple.container."

    static func startSystem(
        appDataRootUrl: URL,
        executablePathUrl: URL,
        timeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let installRootDefaultURL: URL = InstallRoot(executablePathUrl)
            .defaultURL

        try ConfigurationLoader.copyConfigurationToReadOnly(
            to: .init(appDataRootUrl)
        )
        // Pass appRoot before installRoot: ConfigurationLoader uses first-match-wins
        // precedence, so user-provided config in appRoot overrides the defaults
        // shipped under installRoot. Both layers are passed explicitly because
        // users can override --app-root and --install-root from the CLI, and the
        // loader's default search would otherwise ignore those overrides.
        let containerSystemConfig: ContainerSystemConfig =
            try await ConfigurationLoader.load(
                configurationFiles: [
                    ConfigurationLoader.configurationFile(
                        in: .init(appDataRootUrl),
                        of: .appRoot
                    ),
                    ConfigurationLoader.configurationFile(
                        in: .init(installRootDefaultURL),
                        of: .installRoot
                    ),
                ])

        messageStreamContinuation?.yield("Starting System...")

        // Without the true path to the binary in the plist, `container-apiserver` won't launch properly.
        // TODO: Use plugin loader for API server.
        let executableUrl =
            executablePathUrl
            .deletingLastPathComponent()
            .appendingPathComponent("container-apiserver")
            .resolvingSymlinksInPath()

        let args = [executableUrl.absolutePath]

        var apiServerDataUrl = appDataRootUrl.appending(path: "apiserver")
            .resolvingSymlinksInPath()
        if !apiServerDataUrl.isFileURL {
            apiServerDataUrl = URL(filePath: apiServerDataUrl.absolutePath)
        }

        try FileManager.default.createDirectory(
            at: apiServerDataUrl,
            withIntermediateDirectories: true
        )
        var env = PluginLoader.filterEnvironment()
        env[ApplicationRoot.environmentName] = appDataRootUrl.absolutePath
        env[InstallRoot.environmentName] = installRootDefaultURL.absolutePath

        let logURL = apiServerDataUrl.appending(path: "apiserver.log")
        let plist = LaunchPlist(
            label: "\(launchPrefix)apiserver",
            arguments: args,
            environment: env,
            limitLoadToSessionType: [.Aqua, .Background, .System],
            runAtLoad: true,
            stdout: logURL.path,
            stderr: logURL.path,
            machServices: ["\(launchPrefix)apiserver"]
        )

        let plistURL = apiServerDataUrl.appending(path: "apiserver.plist")
        let data = try plist.encode()
        try data.write(to: plistURL)

        try ServiceManager.register(plistPath: plistURL.path)

        // ping api server daemon. Fail if we don't get a response.
        do {
            messageStreamContinuation?.yield(
                "Verifying api server is running..."
            )
            _ = try await ClientHealthCheck.ping(
                timeout: .seconds(timeoutSeconds)
            )
        } catch (let error) {
            throw ContainerizationError(
                .internalError,
                message: "failed to get a response from apiserver: \(error)"
            )
        }
        if await !initImageExists(containerSystemConfig: containerSystemConfig)
        {
            messageStreamContinuation?.yield(
                "Installing base container filesystem..."
            )
            try await installInitialFilesystem(
                initImage: containerSystemConfig.vminit.image,
                messageStreamContinuation: messageStreamContinuation
            )
        }

        guard await !kernelExists() else {
            messageStreamContinuation?.yield("System Started!")
            return
        }

        messageStreamContinuation?.yield("Installing kernel...")
        try await installDefaultKernel(
            kernelURL: containerSystemConfig.kernel.url,
            kernelFilePath: containerSystemConfig.kernel.binaryPath
        )

        messageStreamContinuation?.yield("System Started!")
    }

    static func stopSystem(
        stopContainerTimeoutSeconds: Int32,
        shutdownTimeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let client = ContainerClient()

        let launchdDomainString = try ServiceManager.getDomainString()
        let fullLabel = "\(launchdDomainString)/\(launchPrefix)apiserver"

        messageStreamContinuation?.yield("Stopping containers...")

        do {
            let containers = try await client.list().map { $0.id }
            try await ContainerService.stopContainers(
                containers,
                stopTimeoutSeconds: stopContainerTimeoutSeconds,
                messageStreamContinuation: messageStreamContinuation
            )
        } catch (let error) {
            messageStreamContinuation?.yield("\(error)")
        }

        messageStreamContinuation?.yield("Waiting for containers to exit...")
        do {
            for _ in 0..<shutdownTimeoutSeconds {
                let runningContainers = try await client.list(
                    filters: ContainerListFilters(status: .running)
                )
                guard !runningContainers.isEmpty else {
                    break
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch (let error) {
            messageStreamContinuation?.yield("\(error)")
        }

        messageStreamContinuation?.yield("Stopping Services...")

        try ServiceManager.deregister(fullServiceLabel: fullLabel)
        // Note: The assumption here is that we would have registered the launchd services
        // in the same domain as `launchdDomainString`. This is a fairly sane assumption since
        // if somehow the launchd domain changed, XPC interactions would not be possible.
        try ServiceManager.enumerate()
            .filter { $0.hasPrefix(launchPrefix) }
            .filter { $0 != fullLabel }
            .map { "\(launchdDomainString)/\($0)" }
            .forEach {
                messageStreamContinuation?.yield("Stopping Service: \($0)")
                try? ServiceManager.deregister(fullServiceLabel: $0)
            }

        messageStreamContinuation?.yield("System Stopped!")

    }

    static private func installInitialFilesystem(
        initImage: String,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        try await ImageService.pullImage(
            reference: initImage,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    static private func installDefaultKernel(
        kernelURL: URL,
        kernelFilePath: String
    ) async throws {
        try await ClientKernel.installKernelFromTar(
            tarFile: kernelURL.absoluteString,
            kernelFilePath: kernelFilePath,
            platform: .current,
            force: true
        )
    }

    static private func initImageExists(
        containerSystemConfig: ContainerSystemConfig
    ) async -> Bool {

        do {
            let img = try await ClientImage.get(
                reference: containerSystemConfig.vminit.image,
                containerSystemConfig: containerSystemConfig
            )
            let _ = try await img.getSnapshot(platform: .current)
            return true
        } catch {
            return false
        }
    }

    static private func kernelExists() async -> Bool {
        do {
            try await ClientKernel.getDefaultKernel(for: .current)
            return true
        } catch {
            return false
        }
    }
}
