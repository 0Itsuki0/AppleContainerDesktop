//
//  Network+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/18.
//

import DockerComposeParser

extension DockerComposeParser.Network {
    var mtu: String? {
        return self.driver_opts?["com.docker.network.driver.mtu"] ?? nil
    }

}
