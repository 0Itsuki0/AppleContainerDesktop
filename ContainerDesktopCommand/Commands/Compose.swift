//
//  Compose.swift
//  ContainerDesktopCommand
//
//  Created by Itsuki on 2026/07/20.
//

import ArgumentParser
import Foundation

extension ComposeCommandAction: ExpressibleByArgument {}

struct Compose: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "compose",
        abstract: "Open a compose project with Apple Container Desktop."
    )

    static let supportedComposeFilenames = [
        "compose.yml",
        "compose.yaml",
        "docker-compose.yml",
        "docker-compose.yaml",
    ]

    @Argument(help: "Path to a compose file or a directory containing one.")
    var path: String

    @Argument(help: "Action to perform: up or down. Omit for selecting the project.")
    var action: ComposeCommandAction?

    func run() async throws {
        let composeFile = try Self.resolveComposeFile(at: path)

        var components = URLComponents()
        components.scheme = CustomURLScheme.baseURLScheme
        components.host = "compose"
        var queryItems = [
            URLQueryItem(
                name: "file",
                value: composeFile.standardizedFileURL.absoluteString
            )
        ]
        if let action {
            queryItems.append(
                URLQueryItem(name: "command", value: action.rawValue)
            )
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ValidationError(
                "Failed to construct URL for \(composeFile.path)."
            )
        }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()
    }

    static func resolveComposeFile(at path: String) throws -> URL {
        let url = URL(filePath: path)
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        else {
            throw ValidationError("No file or directory exists at \(url.path).")
        }

        guard isDirectory.boolValue else {
            return url
        }

        for name in supportedComposeFilenames {
            let candidate = url.appendingPathComponent(name)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw ValidationError(
            "No compose file found in \(url.path). Expected one of: \(supportedComposeFilenames.joined(separator: ", "))."
        )
    }
}
