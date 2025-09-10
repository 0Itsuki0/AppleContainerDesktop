//
//  InstallRoot.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/06.
//


import Foundation

struct InstallRoot {
     static let environmentName = "CONTAINER_INSTALL_ROOT"

    private static let envPath = ProcessInfo.processInfo.environment[Self.environmentName]

    let defaultURL: URL
    let url: URL
    let path: String
    
    init(_ executablePath: URL) {
        self.defaultURL = executablePath
            .deletingLastPathComponent()
            .appendingPathComponent("..")
            .standardized
        
        self.url = Self.envPath.map { URL(fileURLWithPath: $0) } ?? defaultURL
        self.path = url.path(percentEncoded: false)
    }
}
