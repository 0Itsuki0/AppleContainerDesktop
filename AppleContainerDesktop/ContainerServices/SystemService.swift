//
//  SystemService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import Foundation

import ContainerClient
import ContainerPersistence
import ContainerPlugin
import ContainerizationError
internal import ContainerizationOCI

class SystemService {
    
    static private let launchPrefix: String = "com.apple.container."

    private enum Dependencies: String {
        case kernel
        case initFs

        var source: String {
            switch self {
            case .initFs:
                return DefaultsStore.get(key: .defaultInitImage)
            case .kernel:
                return DefaultsStore.get(key: .defaultKernelURL)
            }
        }
    }
    
    
    static func startSystem(
        appDataRootUrl: URL,
        executablePathUrl: URL,
        timeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        let installRootDefaultURL: URL = InstallRoot(executablePathUrl).defaultURL
        
        // Without the true path to the binary in the plist, `container-apiserver` won't launch properly.
        // TODO: Use plugin loader for API server.
        let executableUrl = executablePathUrl
            .deletingLastPathComponent()
            .appendingPathComponent("container-apiserver")
            .resolvingSymlinksInPath()

        let args = [executableUrl.absolutePath]

        var apiServerDataUrl = appDataRootUrl.appending(path: "apiserver").resolvingSymlinksInPath()
        if !apiServerDataUrl.isFileURL {
            apiServerDataUrl = URL(filePath: apiServerDataUrl.absolutePath)
        }
        
        try FileManager.default.createDirectory(at: apiServerDataUrl, withIntermediateDirectories: true)
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            key.hasPrefix("CONTAINER_")
        }
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
            messageStreamContinuation?.yield("Verifying api server is running...")
            _ = try await ClientHealthCheck.ping(timeout: .seconds(timeoutSeconds))
        } catch(let error) {
            throw ContainerizationError(
                .internalError,
                message: "failed to get a response from apiserver: \(error)"
            )
        }

        if await !initImageExists() {
            messageStreamContinuation?.yield("Installing base container filesystem...")
            try await installInitialFilesystem(messageStreamContinuation: messageStreamContinuation)
        }

        guard await !kernelExists() else {
            messageStreamContinuation?.yield("System Started!")
            return
        }
        
        messageStreamContinuation?.yield("Installing kernel...")
        try await installDefaultKernel()
        
        messageStreamContinuation?.yield("System Started!")

    }
    
    static func stopSystem(
        stopContainerTimeoutSeconds: Int32,
        shutdownTimeoutSeconds: Int32,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let launchdDomainString = try ServiceManager.getDomainString()
        let fullLabel = "\(launchdDomainString)/\(launchPrefix)apiserver"

        messageStreamContinuation?.yield("stopping containers...")
        
        do {
            let containers = try await ClientContainer.list()
            try await ContainerService.stopContainers(containers: containers, stopTimeoutSeconds: stopContainerTimeoutSeconds, messageStreamContinuation: messageStreamContinuation)
        } catch(let error) {
            messageStreamContinuation?.yield("\(error)")
        }
        
        messageStreamContinuation?.yield("Waiting for containers to exit...")
        do {
            for _ in 0..<shutdownTimeoutSeconds {
                let anyRunning = try await ClientContainer.list()
                    .contains { $0.status == .running }
                guard anyRunning else {
                    break
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch(let error) {
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
 
    static private func installInitialFilesystem(messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {
        let dep = Dependencies.initFs
        try await ImageService.pullImage(reference: dep.source, messageStreamContinuation: messageStreamContinuation)
    }

    static private func installDefaultKernel() async throws {
        let kernelDependency = Dependencies.kernel
        let defaultKernelURL = kernelDependency.source
        let defaultKernelBinaryPath = DefaultsStore.get(key: .defaultKernelBinaryPath)
        
        try await ClientKernel.installKernelFromTar(tarFile: defaultKernelURL, kernelFilePath: defaultKernelBinaryPath, platform: .current, force: true)

    }

    static private func initImageExists() async -> Bool {
        
        do {
            let img = try await ClientImage.get(reference: Dependencies.initFs.source)
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
