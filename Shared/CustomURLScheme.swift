//
//  CustomURLScheme.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2026/07/20.
//

import Foundation

enum CustomURLScheme {
    static let baseURLScheme = "itsuki.enjoy.AppleContainerDesktop"

    case compose(file: URL, action: ComposeCommandAction?)

    enum ParseError: Error, LocalizedError {
        case unrecognizedCommand(String?)
        case missingQuery(String)
        case invalidFileURL(String)
        case invalidAction(String)

        var errorDescription: String? {

            switch self {
            case .unrecognizedCommand(let h):
                return "Unrecognized command: \(h ?? "nil")."
            case .missingQuery(let n): return "Missing '\(n)' query item."
            case .invalidFileURL(let v): return "Invalid file URL: '\(v)'."
            case .invalidAction(let v): return "Invalid action: '\(v)'."
            }
        }
    }

    static func from(url: URL) throws -> CustomURLScheme {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            throw ParseError.unrecognizedCommand(nil)
        }
        let items = components.queryItems ?? []
        switch components.host {
        case "compose": return try compose(from: items)
        default: throw ParseError.unrecognizedCommand(components.host)
        }
    }
}

// Each case owns its own query parsing.
extension CustomURLScheme {
    fileprivate static func compose(from items: [URLQueryItem]) throws
        -> CustomURLScheme
    {
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let fileValue = value("file") else {
            throw ParseError.missingQuery("file")
        }
        guard let fileURL = URL(string: fileValue), fileURL.isFileURL else {
            throw ParseError.invalidFileURL(fileValue)
        }

        var action: ComposeCommandAction? = nil
        if let commandValue = value("command") {
            guard let parsed = ComposeCommandAction(rawValue: commandValue) else {
                throw ParseError.invalidAction(commandValue)
            }
            action = parsed
        }
        return .compose(file: fileURL, action: action)
    }
}
