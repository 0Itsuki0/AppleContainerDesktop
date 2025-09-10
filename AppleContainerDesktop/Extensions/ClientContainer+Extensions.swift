//
//  ClientContainer.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import Foundation

import ContainerClient
internal import ContainerizationOCI

extension ClientContainer {
    
    var imageName: String {
        return self.configuration.image.name
    }
    
    var portsString: String? {
        if self.configuration.publishedPorts.isEmpty {
            return nil
        }
        return self.configuration.publishedPorts.map(\.displayString).joined(separator: "\n")
    }
}


