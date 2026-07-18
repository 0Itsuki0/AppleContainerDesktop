//
//  ImageService.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//

import ContainerAPIClient
import ContainerBuild
import ContainerCommands
import ContainerImagesServiceClient
import ContainerPersistence
import Containerization
import ContainerizationError
internal import ContainerizationOCI
import ContainerizationOS
import Foundation
internal import Logging
import NIO

enum ImageService {

    static func listImages() async throws -> [ClientImage] {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        let images = try await ClientImage.list().filter { image in
            !Utility.isInfraImage(
                name: image.reference,
                builderImage: containerSystemConfig.build.image,
                initImage: containerSystemConfig.vminit.image
            )
        }

        return images
    }

    static func getImage(_ name: String) async throws
        -> ClientImage
    {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()
        let result = try await ClientImage.get(
            names: [name],
            containerSystemConfig: containerSystemConfig
        )
        guard let first = result.images.first else {
            throw ContainerizationError(
                .notFound,
                message: "image not found: \(name)"
            )
        }
        return first
    }

    // pull image from a reference
    static func pullImage(
        reference: String,
        platform: Platform = .current,
        scheme: RequestScheme = RequestScheme.auto,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {

        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        let processedReference = try ClientImage.normalizeReference(
            reference,
            containerSystemConfig: containerSystemConfig
        )

        messageStreamContinuation?.yield("Fetching image...")
        let image = try await ClientImage.pull(
            reference: processedReference,
            platform: platform,
            scheme: scheme,
            containerSystemConfig: containerSystemConfig,
            progressUpdate: { events in
                AdditionalUtility.updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            },
            maxConcurrentDownloads: 3
        )

        messageStreamContinuation?.yield("Unpacking image...")
        try await image.unpack(
            platform: platform,
            progressUpdate: { events in
                AdditionalUtility.updateProgress(
                    events,
                    messageStreamContinuation: messageStreamContinuation
                )
            }
        )
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
        outputs: [BuildImageOutputConfiguration] = [
            .init(type: .oci, additionalFields: [])
        ],
        platforms: Set<Platform> = [Platform.current],
        // build time variable including envs
        buildArguments: [String] = [],
        secrets: [String: Data] = [:],
        labels: [String] = [],
        noCache: Bool = false,
        targetStage: String = "",
        cacheIn: [String] = [],
        cacheOut: [String] = [],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        return try await buildImage(
            dockerFileData: try Data(contentsOf: dockerFile),
            contextDirectory: contextDirectory,
            tag: tag,
            cpus: cpus,
            // memory in bytes
            memory: memory,
            vSockPort: vSockPort,
            outputs: outputs,
            platforms: platforms,
            // build time variable including envs
            buildArguments: buildArguments,
            secrets: secrets,
            labels: labels,
            noCache: noCache,
            targetStage: targetStage,
            // TODO: Add type for cache
            // https://docs.docker.com/reference/cli/docker/buildx/build/#cache-from
            cacheIn: cacheIn,
            cacheOut: cacheOut,
            messageStreamContinuation: messageStreamContinuation
        )

    }

    static func buildImage(
        // file URL, ie: file://
        dockerFileData: Data,
        contextDirectory: URL,
        tag: String,
        cpus: Int64 = 2,
        // memory in bytes
        memory: UInt64 = 1024.mib(),
        vSockPort: UInt32 = 8088,
        outputs: [BuildImageOutputConfiguration] = [
            .init(type: .oci, additionalFields: [])
        ],
        platforms: Set<Platform> = [Platform.current],
        // build time variable including envs
        buildArguments: [String] = [],
        secrets: [String: Data] = [:],
        labels: [String] = [],
        noCache: Bool = false,
        targetStage: String = "",
        // TODO: Add type for cache
        // https://docs.docker.com/reference/cli/docker/buildx/build/#cache-from
        cacheIn: [String] = [],
        cacheOut: [String] = [],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        let ignoreFileURL = URL(
            filePath: ".dockerignore",
            relativeTo: contextDirectory
        )
        let ignoreFileData = try? Data(contentsOf: ignoreFileURL)

        messageStreamContinuation?.yield("Building image...")

        let tag = tag.isEmpty ? UUID().uuidString.lowercased() : tag
        let vsockPort: UInt32 = 8088

        try await BuilderService.startBuilder(
            cpus: cpus,
            memory: memory,
            messageStreamContinuation: messageStreamContinuation
        )

        // wait (seconds) for builder to start listening on vSock
        try await Task.sleep(for: .seconds(5))

        let timeout: Duration = .seconds(120)

        let builder: Builder? = try await withThrowingTaskGroup(
            of: Builder.self
        ) { group in
            defer {
                group.cancelAll()
            }

            group.addTask {
                [vsockPort, cpus, memory, messageStreamContinuation] in
                let client = ContainerClient()
                while true {
                    do {
                        messageStreamContinuation?.yield("Getting Builder...")
                        let fileHandle = try await client.dial(
                            id: "buildkit",
                            port: vsockPort
                        )
                        let threadGroup: MultiThreadedEventLoopGroup =
                            MultiThreadedEventLoopGroup(
                                numberOfThreads: System.coreCount
                            )
                        let b = try Builder(
                            socket: fileHandle,
                            group: threadGroup,
                            logger: Logger.current
                        )

                        // If this call succeeds, then BuildKit is running.
                        let _ = try await b.info()
                        return b
                    } catch {
                        try await BuilderService.startBuilder(
                            cpus: cpus,
                            memory: memory,
                            messageStreamContinuation: messageStreamContinuation
                        )

                        // wait (seconds) for builder to start listening on vSock
                        try await Task.sleep(for: .seconds(5))
                        continue
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw ContainerizationError(
                    .timeout,
                    message: "Timeout waiting for connection to builder"
                )
            }

            return try await group.next()
        }

        guard let builder else {
            throw ContainerizationError(
                .timeout,
                message: "Timeout waiting for connection to builder"
            )
        }

        let systemHealth = try await ClientHealthCheck.ping(
            timeout: .seconds(10)
        )
        let exportPath = systemHealth.appRoot.appendingPathComponent(".build")
        let buildID = UUID().uuidString
        let tempURL = exportPath.appendingPathComponent(buildID)
        try FileManager.default.createDirectory(
            at: tempURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
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

        let config = Builder.BuildConfig(
            buildID: buildID,
            contentStore: RemoteContentStoreClient(),
            buildArgs: buildArguments,
            secrets: secrets,
            contextDir: contextDirectory.absolutePath,
            dockerfile: dockerFileData,
            dockerignore: ignoreFileData,
            labels: labels,
            noCache: noCache,
            platforms: [Platform](platforms),
            terminal: nil,
            tags: [imageName],
            target: targetStage,
            quiet: quiet,
            exports: exports,
            cacheIn: cacheIn,
            cacheOut: cacheOut,
            pull: true,
            containerSystemConfig: containerSystemConfig,
        )

        messageStreamContinuation?.yield("Building Image...")

        try await builder.build(config)

        var finalMessage = "Successfully built \(imageName)..."

        // Currently, only a single export can be specified.
        for exp in exports {
            messageStreamContinuation?.yield("processing export \(exp.type)")
            switch exp.type {
            case BuildImageOutputConfiguration.BuildType.oci.rawValue:
                try Task.checkCancellation()
                guard let dest = exp.destination else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "dest is required \(exp.rawValue)"
                    )
                }
                let result = try await ClientImage.load(
                    from: dest.absolutePath,
                    force: false
                )
                guard result.rejectedMembers.isEmpty else {
                    throw ContainerizationError(
                        .internalError,
                        message: "failed to load archive"
                    )
                }
                for image in result.images {
                    try Task.checkCancellation()
                    try await image.unpack(
                        platform: nil,
                        progressUpdate: { events in
                            AdditionalUtility.updateProgress(
                                events,
                                messageStreamContinuation:
                                    messageStreamContinuation
                            )
                        }
                    )
                }

            case BuildImageOutputConfiguration.BuildType.tar.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "destination is required."
                    )
                }
                let tarURL = tempURL.appendingPathComponent("out.tar")
                try FileManager.default.moveItem(at: tarURL, to: dest)
                finalMessage = "Successfully exported to \(dest.absolutePath)"

            case BuildImageOutputConfiguration.BuildType.local.rawValue:
                guard let dest = exp.destination else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "destination is required."
                    )
                }
                let localDir = tempURL.appendingPathComponent("local")

                guard FileManager.default.fileExists(atPath: localDir.path)
                else {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "expected local output not found"
                    )
                }
                try FileManager.default.copyItem(at: localDir, to: dest)
                finalMessage = "Successfully exported to \(dest.absolutePath)"
            default:
                throw ContainerizationError(
                    .invalidArgument,
                    message: "invalid exporter."
                )
            }
        }

        messageStreamContinuation?.yield(finalMessage)
    }

    static func saveImages(
        _ images: [ClientImage],
        platform: Platform = .current,
        outputDirectory: URL,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        messageStreamContinuation?.yield("Saving \(images.count) Image(s)...")

        let references: [String] = images.map(\.reference)
        let outputPath = outputDirectory.appending(
            path: "\(Date().ISO8601Format()).tar"
        ).absolutePath
        try await ClientImage.save(
            references: references,
            out: outputPath,
            platform: platform,
            containerSystemConfig: containerSystemConfig
        )

        messageStreamContinuation?.yield("Saved \(images.count) Image(s)...")
    }

    static func loadImages(
        tar: URL,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let path = tar.absolutePath

        guard FileManager.default.fileExists(atPath: path) else {
            throw ContainerizationError(
                .invalidArgument,
                message: "File Does not exist."
            )
        }

        messageStreamContinuation?.yield(
            "Loading image from \(tar.lastPathComponent.isEmpty ? path : tar.lastPathComponent)..."
        )

        let result = try await ClientImage.load(from: path, force: false)

        messageStreamContinuation?.yield("Unpacking Images")

        for image in result.images {
            try await image.unpack(
                platform: nil,
                progressUpdate: { events in
                    AdditionalUtility.updateProgress(
                        events,
                        messageStreamContinuation: messageStreamContinuation
                    )
                }
            )
        }
    }

    static func deleteImages(
        _ images: [String],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()
        let result = try await ClientImage.get(
            names: images,
            containerSystemConfig: containerSystemConfig
        )
        // NOTE: not check result.error here in case it is just image not found.
        try await deleteImages(
            result.images,
            messageStreamContinuation: messageStreamContinuation
        )
    }

    static func deleteImages(
        _ images: [ClientImage],
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        let containerSystemConfig: ContainerSystemConfig =
            try await Application.loadContainerSystemConfig()

        messageStreamContinuation?.yield("Deleting \(images.count) image(s)...")

        var failed: [(String, Error)] = []
        var didDeleteAnyImage: Bool = false
        for image in images {
            guard
                !Utility.isInfraImage(
                    name: image.reference,
                    builderImage: containerSystemConfig.build.image,
                    initImage: containerSystemConfig.vminit.image
                )
            else {
                continue
            }
            do {
                try await ClientImage.delete(
                    reference: image.reference,
                    garbageCollect: false
                )
                didDeleteAnyImage = true
                messageStreamContinuation?.yield(
                    "Image deleted: \(image.reference)"
                )
            } catch (let error) {
                if error.isResourceNotFound {
                    continue
                }
                messageStreamContinuation?.yield(
                    "failed to delete image \(image.reference): \(error)"
                )
                failed.append((image.reference, error))
            }
        }

        let (_, size) = try await ClientImage.cleanUpOrphanedBlobs()
        let freed = Formatter.byteCountFormatter.string(
            fromByteCount: Int64(size)
        )

        if didDeleteAnyImage {
            messageStreamContinuation?.yield("Reclaimed \(freed) in disk space")
        }
        if failed.count > 0 {
            throw ContainerizationError(
                .internalError,
                message:
                    "failed to delete one or more images: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
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
    // for OCi, will use a temporary URL specific for the build
    var destinationDirectory: URL?

    private var destination: URL? {
        switch self.type {
        case .local:
            destinationDirectory?.appending(
                path: "\(Date().ISO8601Format()).tar"
            )
        case .tar:
            destinationDirectory?.appending(
                path: "\(Date().ISO8601Format()).tar"
            )
        case .oci:
            // specifying oci output destination while building will result in failure.
            // Error: unknown: "Error Domain=NSCocoaErrorDomain Code=4 "The file “dest” doesn’t exist." UserInfo={NSFilePath=/Users/.../dest, NSUnderlyingError=0x81fc32b80 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}"
            nil
        }
    }

    var additionalFields: [KeyValueModel]

    var buildExport: Builder.BuildExport {
        var rawInput = AdditionalUtility.keyValueString(
            key: "type",
            value: type.rawValue
        )
        if let destination {
            rawInput =
                "\(rawInput),\(AdditionalUtility.keyValueString(key: "dest", value: destination.path(percentEncoded: true)))"
        }
        if !additionalFields.isEmpty {
            let additionalFieldString = additionalFields.stringArray.joined(
                separator: ","
            )
            rawInput = "\(rawInput),\(additionalFieldString)"
        }
        return .init(
            type: type.rawValue,
            destination: destination,
            additionalFields: additionalFields.dictRepresentation,
            rawValue: rawInput
        )
    }

    func verify() throws {
        guard let destinationDirectory = self.destinationDirectory else {
            if self.type == .oci {
                return
            }

            throw ContainerizationError(
                .invalidArgument,
                message:
                    "Destination required for output type \(self.type.rawValue)"
            )
        }

        if self.type == .oci {
            throw ContainerizationError(
                .invalidArgument,
                message: "Destination cannot be specified for OCI."
            )

        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: destinationDirectory.absolutePath)
        else {
            throw ContainerizationError(
                .invalidArgument,
                message: "Destination directory does not exist."
            )
        }

        if !destinationDirectory.isDirectory {
            throw ContainerizationError(
                .invalidArgument,
                message: "Specified Destination is not a directory."
            )
        }
    }
}
