//
//  PublishPort.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/09.
//


import Foundation
import ContainerResource

extension PublishPort {
    var displayString: String {
        "\(self.hostPort):\(self.containerPort) (\(self.proto.rawValue.localizedUppercase))"
    }
}
