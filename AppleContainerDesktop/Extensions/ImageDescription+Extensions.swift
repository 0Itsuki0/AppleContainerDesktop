//
//  ImageDescription.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import ContainerClient
internal import ContainerizationOCI

extension ImageDescription {
    var name: String {
        guard let annotations = self.descriptor.annotations else {
            return self.reference
        }
        if let name = annotations[AnnotationKeys.containerizationImageName] {
            return name
        }

        if let name = annotations[AnnotationKeys.containerdImageName] {
            return name
        }
        if let name = annotations[AnnotationKeys.openContainersImageName] {
            return name
        }

        return self.reference

    }
}
