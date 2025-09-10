//
//  ImageDisplayModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/07.
//

import Foundation

import ContainerClient
internal import ContainerizationOCI


struct ImageDisplayModel: Identifiable {

    var name: String
    var tag: String
    var indexDigest: String
    var os: String
    var arch: String
    var variant: String
    var size: String
    var created: String
    var manifestDigest: String
    
    var inUseContainers: [ClientContainer]
    var inUse: Bool {
        return !inUseContainers.isEmpty
    }
    
    var image: ClientImage
    
    var id: String {
        return indexDigest + manifestDigest
    }
    
    init?(_ image: ClientImage, containers: [ClientContainer]) async throws {
        let imageDigest = try await image.resolved().digest
        
        for descriptor in try await image.index().manifests {
            // Don't list attestation manifests
            if let referenceType = descriptor.annotations?["vnd.docker.reference.type"],
                referenceType == "attestation-manifest" {
                continue
            }

            guard let platform = descriptor.platform else { continue }

            let os = platform.os
            let arch = platform.architecture
            let variant = platform.variant ?? ""

            var config: ContainerizationOCI.Image
            var manifest: ContainerizationOCI.Manifest
            do {
                config = try await image.config(for: platform)
                manifest = try await image.manifest(for: platform)
            } catch {
                continue
            }

            let created = config.created ?? ""
            let size = descriptor.size + manifest.config.size + manifest.layers.reduce(0, { (l, r) in l + r.size })
            let formattedSize = Formatter.byteCountFormatter.string(fromByteCount: size)

            let processedReferenceString = try ClientImage.denormalizeReference(image.reference)
            let reference = try ContainerizationOCI.Reference.parse(processedReferenceString)
            
            self.name = reference.name
            self.tag = reference.tag ?? "<none>"
            self.indexDigest = imageDigest
            self.os = os.localizedCapitalized
            self.arch = arch.localizedCapitalized
            self.variant = variant
            self.created = created
            self.size = formattedSize
            self.manifestDigest = descriptor.digest
            self.image = image
            self.inUseContainers = containers.filter({$0.configuration.image.digest == image.description.digest})
            
            return
        }
        
        return nil
        
    }
    
}



