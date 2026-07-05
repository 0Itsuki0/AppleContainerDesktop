//
//  VolumeDisplayModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/11/03.
//

import Foundation
import ContainerResource
import ContainerAPIClient

@dynamicMemberLookup
struct VolumeDisplayModel: Identifiable {
    var volume: VolumeConfiguration
    
    var created: String {
        return Formatter.dateFormatter.string(from: volume.creationDate)
    }
    
    var size: String? {
        guard let volumeSize = volume.sizeInBytes else {
            return nil
        }
        let formattedSize = Formatter.byteCountFormatter.string(fromByteCount: Int64(volumeSize))
        return formattedSize
    }
    
    var id: String {
        return volume.id
    }
    
    var inUseContainers: [ContainerSnapshot]
    var inUse: Bool {
        return !inUseContainers.isEmpty
    }
    
    var volumeType: VolumeType {
        self.volume.isAnonymous ? .anonymous : .named
    }
    
    var labels: [String : String] {
        self.volume.labels.filter({$0.key != VolumeConfiguration.anonymousLabel})
    }
    
    var options: [String : String] {
        self.volume.options.filter({$0.key != VolumeConfiguration.sizeOptionKey})
    }

    init(_ volume: VolumeConfiguration, containers: [ContainerSnapshot]) {
        self.volume = volume
        self.inUseContainers = containers.filter({ container in
            container.volumeNames.contains(volume.name)
        })
    }

}

extension VolumeDisplayModel {
    subscript<T>(dynamicMember keyPath: KeyPath<VolumeConfiguration, T>) -> T {
        return volume[keyPath: keyPath]
    }
}
