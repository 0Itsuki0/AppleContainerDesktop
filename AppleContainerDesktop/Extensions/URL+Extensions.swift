//
//  URL+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/19.
//

import Foundation

extension URL {
    nonisolated
    var absolutePath: String {
        return self.path(percentEncoded: false)
    }
    
    nonisolated
    var parentDirectory: URL {
        return self.appending(component: "..").standardized
    }
}
