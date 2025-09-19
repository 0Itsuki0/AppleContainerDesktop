//
//  ImageService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import Foundation

import ContainerClient
import ContainerizationError
internal import ContainerizationOCI
import ContainerBuild
import ContainerClient
import ContainerImagesServiceClient
import Containerization
import ContainerizationError
import ContainerizationOS
import Foundation
import NIO


class ImageService {
    
    static func listImages() async throws -> [ClientImage] {
        let images = try await ClientImage.list().filter { image in
            !Utility.isInfraImage(name: image.reference)
        }
        
        return images
    }
    
    // pull image from a reference
    static func pullImage(
        reference: String,
        platform: Platform = .current,
        scheme: String = RequestScheme.auto.rawValue,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        
        let scheme = try RequestScheme(scheme)

        let processedReference = try ClientImage.normalizeReference(reference)

        messageStreamContinuation?.yield("Fetching image...")
        let image = try await ClientImage.pull(
            reference: processedReference, platform: platform, scheme: scheme, progressUpdate: { events in
                Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )

        messageStreamContinuation?.yield("Unpacking image...")
        try await image.unpack(platform: platform, progressUpdate: { events in
            Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
        })
    }
    
    
    
    // build image from Dockerfile
    // https://docs.docker.com/reference/cli/docker/buildx/build/#target
    static func buildImage(
        // file URL, ie: file://
        dockerFile: URL,
        contextDirectory: URL,
        tag: String,
        cpus: Int64 = 2,
        // memory in bytes
        memory: UInt64 = 1024.mib(),
        vSockPort: UInt32 = 8088,
        outputs: [BuildImageOutputConfiguration] = [.init(type: .oci, additionalFields: [])],
        platforms: Set<Platform> = [Platform.current],
        // build time variable
        buildArguments: [KeyValueModel] = [],
        labels: [KeyValueModel] = [],
        noCache: Bool = false,
        targetStage: String = "",
        // TODO: Add type for cache
        // https://docs.docker.com/reference/cli/docker/buildx/build/#cache-from
        cacheIn: [String] = [],
        cacheOut: [String] = [],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        
        let tag = tag.isEmpty ? UUID().uuidString.lowercased() : tag
        
        try await BuilderService.startBuilder(cpus: cpus, memory: memory, messageStreamContinuation: messageStreamContinuation)
        
        // wait (seconds) for builder to start listening on vSock
        try await Task.sleep(for: .seconds(5))

        let timeout: Duration = .seconds(120)

        let builder: Builder? = try await withThrowingTaskGroup(of: Builder.self) { group in
            defer {
                group.cancelAll()
            }

            group.addTask {
                while true {
                    do {
                        messageStreamContinuation?.yield("Getting Builder...")
                        let container = try await ClientContainer.get(id: BuilderService.buildkitContainerId)
                        
                        messageStreamContinuation?.yield("Dialing Builder...")
                        let fileHandle = try await container.dial(vSockPort)
                        let threadGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
                        let b = try Builder(socket: fileHandle, group: threadGroup)

                        // If this call succeeds, then BuildKit is running.
                        let _ = try await b.info()
                        return b
                    } catch {
                        // wait (seconds) for builder to start listening on vSock
                        try await Task.sleep(for: .seconds(5))
                        continue
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw ContainerizationError(.timeout, message: "Timeout waiting for connection to builder")
            }

            return try await group.next()
        }

        guard let builder else {
            throw ContainerizationError(.timeout, message: "Timeout waiting for connection to builder")
        }

        let dockerFileData = try Data(contentsOf: dockerFile)
        let systemHealth = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let exportPath = systemHealth.appRoot.appendingPathComponent(".build")
        let buildID = UUID().uuidString
        let tempURL = exportPath.appendingPathComponent(buildID)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let imageName: String = try {
            let parsedReference = try Reference.parse(tag)
            parsedReference.normalize()
            return parsedReference.description
        }()


        let exports: [Builder.BuildExport] = try outputs.map { output in
            try output.verify()
            var export = output.buildExport
            if export.destination == nil {
                export.destination = tempURL.appendingPathComponent("out.tar")
            }
            return export
        }
        
        var quiet = true
        #if DEBUG
        quiet = false
        #endif
        
        let config = Builder.BuildConfig.init(
            buildID: buildID,
            contentStore: RemoteContentStoreClient(),
            buildArgs: buildArguments.stringArray,
            contextDir: contextDirectory.absolutePath,
            dockerfile: dockerFileData,
            labels: labels.stringArray,
            noCache: noCache,
            platforms: [Platform](platforms),
            terminal: nil,
            tag: imageName,
            target: targetStage,
            quiet: quiet,
            exports: exports,
            cacheIn: cacheIn,
            cacheOut: cacheOut
        )
        
        messageStreamContinuation?.yield("Building Image...")

        try await builder.build(config)

        var finalMessage = "Successfully built \(imageName)..."

        // Currently, only a single export can be specified.
        for exp in exports {
            switch exp.type {
            case BuildImageOutputConfiguration.BuildType.oci.rawValue:
                try Task.checkCancellation()
                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "dest is required \(exp.rawValue)")
                }
                let loaded = try await ClientImage.load(from: dest.absolutePath)
                for image in loaded {
                    try Task.checkCancellation()
                    try await image.unpack(platform: nil, progressUpdate: { events in
                        Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
                    })
                }
            case BuildImageOutputConfiguration.BuildType.tar.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "destination is required.")
                }
                let tarURL = tempURL.appendingPathComponent("out.tar")
                try FileManager.default.moveItem(at: tarURL, to: dest)
                finalMessage = "Successfully exported to \(dest.absolutePath)"
            case BuildImageOutputConfiguration.BuildType.local.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(.invalidArgument, message: "destination is required.")
                }
                let localDir = tempURL.appendingPathComponent("local")

                guard FileManager.default.fileExists(atPath: localDir.path) else {
                    throw ContainerizationError(.invalidArgument, message: "expected local output not found")
                }
                try FileManager.default.copyItem(at: localDir, to: dest)
                finalMessage = "Successfully exported to \(dest.absolutePath)"
            default:
                throw ContainerizationError(.invalidArgument, message: "invalid exporter.")
            }
        }
        
        messageStreamContinuation?.yield(finalMessage)

    }
    
    
    static func deleteImages(_ images: [ClientImage], messageStreamContinuation: AsyncStream<String>.Continuation?) async throws {
        var failed: [(String, Error)] = []
        var didDeleteAnyImage: Bool = false
        for image in images {
            guard !Utility.isInfraImage(name: image.reference) else {
                continue
            }
            do {
                try await ClientImage.delete(reference: image.reference, garbageCollect: false)
                didDeleteAnyImage = true
                messageStreamContinuation?.yield("Image deleted: \(image.reference)")
            } catch(let error) {
                messageStreamContinuation?.yield("failed to delete image \(image.reference): \(error)")
                failed.append((image.reference, error))
            }
        }
        
        let (_, size) = try await ClientImage.pruneImages()
        let freed = Formatter.byteCountFormatter.string(fromByteCount: Int64(size))

        if didDeleteAnyImage {
            messageStreamContinuation?.yield("Reclaimed \(freed) in disk space")
        }
        if failed.count > 0 {
            throw ContainerizationError(
                .internalError,
                message: "failed to delete one or more images: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }
}


struct BuildImageOutputConfiguration {
    enum BuildType: String, Identifiable {
        case oci
        case tar
        case local
        
        var id: String {
            return self.rawValue
        }
        
        var description: String {
            switch self {
            case .oci:
                "Export an OCI(Open Container Initiative)."
            case .tar:
                "Exports files as a tar archive."
            case .local:
                "Exports files to a local directory."
            }
        }
        var title: String {
            switch self {
                
            case .oci:
                "OCI"
            case .tar:
                "tar"
            case .local:
                "local"
            }
        }
    }
    
    
    var type: BuildType
    
    // required for local and tar
    // for OCi, will use a temporary URL sepecific for the build
    var destination: URL?
    
    var additionalFields: [KeyValueModel]
    
    var buildExport: Builder.BuildExport {
        var rawInput = Utility.keyValueString(key: "type", value: type.rawValue)
        if let destination {
            rawInput = "\(rawInput),\(Utility.keyValueString(key: "dest", value: destination.path(percentEncoded: true)))"
        }
        if !additionalFields.isEmpty {
            let additionalFieldString = additionalFields.stringArray.joined(separator: ",")
            rawInput = "\(rawInput),\(additionalFieldString)"
        }
        return .init(type: type.rawValue, destination: destination, additionalFields: additionalFields.dictRepresentation, rawValue: rawInput)
    }
    
    
    // TODO: Add validation on URL
    func verify() throws {
//            let destination = URL(fileURLWithPath: dest)
//            let fileManager = FileManager.default
//
//            if fileManager.fileExists(atPath: destination.path) {
//                let resourceValues = try destination.resourceValues(forKeys: [.isDirectoryKey])
//                let isDir = resourceValues.isDirectory
//                if isDir != nil && isDir == false {
//                    throw Builder.Error.invalidExport(dest, "dest path already exists")
//                }
//
//                var finalDestination = destination.appendingPathComponent("out.tar")
//                var index = 1
//                while fileManager.fileExists(atPath: finalDestination.path) {
//                    let path = "out.tar.\(index)"
//                    finalDestination = destination.appendingPathComponent(path)
//                    index += 1
//                }
//                return finalDestination
//            } else {
//                let parentDirectory = destination.deletingLastPathComponent()
//                try? fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
//            }

    }

}
