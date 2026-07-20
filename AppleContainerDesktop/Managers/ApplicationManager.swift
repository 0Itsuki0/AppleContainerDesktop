//
//  ContainerManager.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/04.
//

internal import Logging
import SwiftUI

enum DisplayCategory: String, Identifiable, Equatable {
    // section 1
    case container
    case image
    case volume
    case network

    // section 2
    case compose

    var displayTitle: String {
        switch self {
        case .container:
            "Containers"
        case .image:
            "Images"
        case .volume:
            "Volumes"
        case .network:
            "Networks"
        case .compose:
            "Composes"
        }
    }

    var icon: String {
        switch self {
        case .container:
            "cube.fill"
        case .image:
            "cloud.fill"
        case .volume:
            "internaldrive.fill"
        case .network:
            "network"
        case .compose:
            "square.grid.2x2.fill"
        }
    }

    var id: String {
        self.rawValue
    }

    static let allCases: [[DisplayCategory]] = [
        [.image, .container, .volume, .network], [.compose],
    ]
}

@Observable
class ApplicationManager {
    static let containerGithub: URL? = URL(
        string: "https://github.com/apple/container"
    )

    static var logger: Logger {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        var logger = Logger(label: "itsuki.enjoy.AppleContainerDesktop")
        #if DEBUG
            logger.logLevel = .info
        #else
            logger.logLevel = .error
        #endif

        return logger
    }

    var error: Error? {
        didSet {
            if let error = self.error {
                print(error)
                self.showError = true
                self.showProgressView = false
            }
        }
    }

    var showError: Bool = false {
        didSet {
            if !showError {
                self.error = nil
            }
        }
    }

    var isSystemRunning: Bool = false

    var selectedCategory: DisplayCategory = .image {
        didSet {
            self.selectedContainerID = nil
        }
    }

    var selectedContainerID: ContainerSnapshotID?
    var refreshContainerNeeded: Bool = false

    var pendingComposeAction: ComposeAction? {
        didSet {
            if self.pendingComposeAction != nil {
                self.selectedCategory = .compose
            }
        }
    }

    var showProgressView: Bool = false {
        didSet {
            if self.showProgressView {
                progressMessage = "Loading..."
            }
        }
    }
    var progressMessage: String = "Loading..."
    let messageStream: AsyncStream<String>
    let messageStreamContinuation: AsyncStream<String>.Continuation
    @ObservationIgnored private var messageTask: Task<Void, Error>?

    init() {
        (messageStream, messageStreamContinuation) = AsyncStream<String>
            .makeStream()
        self.messageTask = Task {
            for await message in messageStream {
                if !message.isEmpty {
                    print(message)
                    self.progressMessage = message
                }
            }
        }
    }

    deinit {
        self.messageTask?.cancel()
        self.messageTask = nil

        Task {
            try? await SystemService.stopSystem(
                stopContainerTimeoutSeconds: UserSettingsManager
                    .defaultStopContainerTimeoutSeconds,
                shutdownTimeoutSeconds: UserSettingsManager
                    .defaultShutdownSystemTimeoutSeconds,
                messageStreamContinuation: nil
            )
        }
    }

    func onOpenURL(_ url: URL) {
        do {
            let scheme = try CustomURLScheme.from(url: url)
            switch scheme {
            case .compose(let file, let action):
                try self.handleComposeURL(file: file, action: action)
            }
        } catch {
            print("Error handling URL:", error)
        }
    }

    private func handleComposeURL(file: URL, action: ComposeCommandAction?)
        throws
    {
        let allComposes = ComposeService.listComposeResources()
        let compose: ComposeResource
        // existing
        if let existing = allComposes.first(where: {
            $0.baseCompose.absolutePath == file.absolutePath
        }) {
            compose = existing
        } else {
            // create new compose
            compose = ComposeResource(
                baseCompose: file,
                projectDirectory: nil,
                additionalComposes: [],
                envFiles: [],
                nameOverride: nil
            )
            // save the newly created one
            try ComposeService.addComposeResources([compose])
        }

        self.pendingComposeAction = .init(
            compose: compose,
            actionCategory: action?.actionCategory ?? .inspect
        )
    }
}

extension ComposeCommandAction {
    var actionCategory: ComposeActionCategory {
        switch self {
        case .up: .up
        case .down: .down
        }
    }
}
