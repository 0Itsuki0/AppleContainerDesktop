//
//  ClientContainer.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import Foundation


internal import ContainerizationOCI
import ContainerResource

extension ContainerSnapshot {
    
    var imageName: String {
        return self.configuration.image.name
    }
    
    var portsString: String? {
        if self.configuration.publishedPorts.isEmpty {
            return nil
        }
        return self.configuration.publishedPorts.map(\.displayString).joined(separator: "\n")
    }
    
    var volumeFSs: [Filesystem] {
        let fileSystems = self.configuration.mounts
        let volumes = fileSystems.filter({ $0.isVolume })
        return volumes
    }
    
    var volumeNames: [String] {
        let volumeNames = self.volumeFSs.map(\.volumeName).filter({$0 != nil}).map({$0!})
        return volumeNames
    }

}
