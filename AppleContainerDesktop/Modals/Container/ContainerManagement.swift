//
//  ContainerManagement.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import Foundation
internal import ContainerizationOCI
import ContainerClient

 struct ContainerManagement {
     // Override the entryPoint of the image
     var entryPoint: String?

     // virtual filesystem mount
     var virtualFileSystem: [Filesystem] = []
     
     // volume mount
     var volumes: [Filesystem] = []

     // Published ports from container to host
     // format: [host-ip:]host-port:container-port[/protocol]
     var publishPorts: [PublishPort] = []

     // Published sockets from container to host
     // format: host_path:container_path
     var publishSockets: [PublishSocket] = []

     // temporary File system mount mount at a given path
     var temporaryFileSystem: [Filesystem] = []
     
     // Assign a name to the container. If empty, will be a generated UUID
     var name: String = ""

     // Remove the container after it stops
     var remove = false

     // Platform for the image if it's multi-platform
     var platform: String?

     // Set OS if image can target multiple operating systems
     var os = "linux"

     // Set arch if image can target multiple architectures
     var arch: String = Arch.hostArchitecture().rawValue


     // Full file path to a custom kernel
     // ie: File:// ...
     var kernel: String?

     // Attach the container to a network
     var networks: [String] = []


     // Write the container ID to the path provided
     var cidfile = ""

     // Do not configure DNS in the container
     var dnsDisabled = false

     // DNS nameserver IP address
     var dnsNameservers: [String] = []

     // Default DNS domain
     var dnsDomain: String? = nil

     // DNS search domains
     var dnsSearchDomains: [String] = []

     // DNS options
     var dnsOptions: [String] = []

     // Add key: value labels to the container
     var labels: [String: String] = [:]

     // Expose virtualization capabilities to the container. (Host must have nested virtualization support, and guest kernel must have virtualization capabilities enabled)
     var virtualization: Bool = false

     // Forward SSH agent socket to container
     var ssh = false
}
