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

class ImageService {
    
    static func listImages() async throws -> [ClientImage] {
        let images = try await ClientImage.list().filter { image in
            !Utility.isInfraImage(name: image.reference)
        }
        
        return images
    }
    
    static func pullImage(
        reference: String,
        platform: String? = nil,
        scheme: String = RequestScheme.auto.rawValue,
        os: String = "linux",
        arch: String = Arch.hostArchitecture().rawValue,
        messageStreamContinuation: AsyncStream<String>.Continuation?
    ) async throws {
        
        var p: Platform?
        if let platform {
            p = try Platform(from: platform)
        } else {
            p = try Platform(from: "\(os)/\(arch)")
        }

        let scheme = try RequestScheme(scheme)

        let processedReference = try ClientImage.normalizeReference(reference)

        messageStreamContinuation?.yield("Fetching image...")
        let image = try await ClientImage.pull(
            reference: processedReference, platform: p, scheme: scheme, progressUpdate: { events in
                Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
            }
        )

        messageStreamContinuation?.yield("Unpacking image...")
        try await image.unpack(platform: p, progressUpdate: { events in
            Utility.updateProgress(events, messageStreamContinuation: messageStreamContinuation)
        })
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
