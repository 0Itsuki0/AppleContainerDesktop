//
//  Error+Extensions.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/17.
//

import ContainerizationError
import Foundation

nonisolated extension Error {
    var isResourceNotFound: Bool {
        if let error = self as? ContainerizationError,
            error.isCode(.notFound)
        {
            return true
        }
        return false
    }
}
