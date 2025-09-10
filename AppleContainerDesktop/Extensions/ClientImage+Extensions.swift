//
//  ClientImage.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import Foundation

import ContainerClient
import ContainerizationError
internal import ContainerizationOCI

extension ClientImage {
    func resolved() async throws -> Descriptor {
        let index = try await self.index()
        let indirect = index.annotations?[AnnotationKeys.containerizationIndexIndirect]
        // If this is not an indirect index, return its own descriptor
        guard let indirect, ["1", "true"].contains(indirect.lowercased()) else {
            return self.descriptor
        }
        // For indirect indices, return the first (and only) manifest
        guard let manifest = index.manifests.first else {
            throw ContainerizationError(
                .internalError,
                message: "Failed to resolve indirect index \(self.digest): no manifests found"
            )
        }
        return manifest
    }
}
