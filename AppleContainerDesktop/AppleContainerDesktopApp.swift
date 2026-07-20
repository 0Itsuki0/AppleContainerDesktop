//
//  AppleContainerDesktopApp.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/04.
//

import SwiftUI

@main
struct AppleContainerDesktopApp: App {
    static let dashboardWindowId = "dashboard"

    private let applicationManager = ApplicationManager()
    private let userSettingsManager = UserSettingsManager()

    var body: some Scene {

        Window(
            "Apple Container Desktop",
            id: Self.dashboardWindowId,
            content: {
                ContentView()
//                TestView()
//                ComposeListView()
                    .environment(applicationManager)
                    .environment(userSettingsManager)
            }
        )
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra(
            content: {
                AppMenu()
                    .environment(applicationManager)
                    .environment(userSettingsManager)

            },
            label: {
                Image(systemName: "cube.fill")
            }
        )
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(userSettingsManager)
                .fixedSize(horizontal: true, vertical: true)
        }
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

    }
}

struct TestView: View {
    var (messageStream, messageStreamContinuation) = AsyncStream<String>
        .makeStream()

    var body: some View {
        VStack {
            Button(
                action: {
                    testExec()
                },
                label: {
                    Text("test exec")
                }
            )

            Button(
                action: {
                    testBuild()
                },
                label: {
                    Text("Up compose")
                }
            )

            Button(
                action: {
                    testdown(shouldRemove: false)
                },
                label: {
                    Text("down compose")
                }
            )

            Button(
                action: {
                    testdown(shouldRemove: true)
                },
                label: {
                    Text("rm compose")
                }
            )

        }
        .task {
            for await message in messageStream {
                print(message)
            }
        }

    }

    func testExec() {
        Task {
            do {
                let exitCode = try await ContainerService.executeCommand(
                    on: "ComposeTest_redis",
                    arguments: ["redis-cli", "ping"],
                    processFlags: .init(),
                    detach: false,
                    onStdout: {
                        print("output", $0)
                    },
                    onStderr: {
                        print("error", $0)
                    }
                )
                print("exitCode: \(exitCode, default: "nil")")
            } catch (let error) {
                print(error)
            }
        }
    }

    func testBuild() {
        let baseURL = URL(
            filePath: "/Users/itsuki/Desktop/ComposeTest/compose.yaml"
        )

        Task {
            do {
                let result = try await ComposeService.upCompose(
                    baseURL,
                    forceRebuild: false,
                    forceRecreate: false,
                    messageStreamContinuation: messageStreamContinuation
                )
                //                print(result.map({$0.key}))
            } catch (let error) {
                print(error)
            }
        }
    }

    func testdown(shouldRemove: Bool) {
        let baseURL = URL(
            filePath: "/Users/itsuki/Desktop/ComposeTest/compose.yaml"
        )

        Task {
            do {
                try await ComposeService.downCompose(
                    baseURL,
                    shouldRemove: shouldRemove,
                    messageStreamContinuation: messageStreamContinuation
                )
                //                print(result.map({$0.key}))
            } catch (let error) {
                print(error)
            }
        }
    }
    
//    private func handleSave(override: Bool = false) {
//        let baseURL = URL(
//            filePath: "/Users/itsuki/Desktop/ComposeTest/compose.yaml"
//        )
//
//        do {
//            let compose = try ComposeResource(
//                baseCompose: baseURL,
//                projectDirectory: nil,
//                additionalComposes: [],
//                envFiles: [],
//                nameOverride: nil
//            )
//            
//            if !override, ComposeService.composeExist(name: compose.name) {
//                self.conflictingName = compose.name
//                return
//            }
//
//            try ComposeService.saveComposes([compose])
//            self.dismiss()
//        } catch {
//            self.errorMessage = error.localizedDescription
//        }
//
//    }


}
