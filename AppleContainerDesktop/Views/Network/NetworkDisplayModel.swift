//
//  NetworkDisplayModel.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import Foundation
import ContainerResource
import ContainerAPIClient
import ContainerizationExtras

@dynamicMemberLookup
struct NetworkDisplayModel: Identifiable {
    var network: NetworkResource

    var created: String {
        return Formatter.dateFormatter.string(from: network.creationDate)
    }

    var id: String {
        return network.id
    }

    var inUseContainers: [ContainerSnapshot]
    var inUse: Bool {
        return !inUseContainers.isEmpty
    }

    var mode: NetworkMode {
        self.network.configuration.mode
    }

    var ipv4Subnet: String {
        self.network.status.ipv4Subnet.description
    }

    var ipv4Gateway: String {
        self.network.status.ipv4Gateway.description
    }

    var ipv6Subnet: String? {
        self.network.status.ipv6Subnet?.description
    }

    var plugin: String {
        self.network.configuration.plugin
    }

    var labels: [String: String] {
        self.network.labels.dictionary
    }

    var options: [String: String] {
        self.network.configuration.options
    }

    init(_ network: NetworkResource, containers: [ContainerSnapshot]) {
        self.network = network
        self.inUseContainers = containers.filter({ container in
            container.networkNames.contains(network.name)
        })
    }

}

extension NetworkDisplayModel {
    subscript<T>(dynamicMember keyPath: KeyPath<NetworkResource, T>) -> T {
        return network[keyPath: keyPath]
    }
}

extension ContainerSnapshot {
    var networkNames: [String] {
        return self.configuration.networks.map(\.network)
    }
}
