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
        
        Window("Apple Container Desktop", id: Self.dashboardWindowId, content: {
            ContentView()
                .environment(applicationManager)
                .environment(userSettingsManager)
        })
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        
        
        MenuBarExtra(content: {
            AppMenu()
                .environment(applicationManager)
                .environment(userSettingsManager)

        }, label: {
            Image(systemName: "cube.fill")
        })
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
