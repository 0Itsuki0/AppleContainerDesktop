//
//  CustomProgressView.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI

struct CustomProgressView: View {
    @Environment(ApplicationManager.self) private var applicationManager
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text(applicationManager.progressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .controlSize(.extraLarge)
        .padding(.all, 24)
        .frame(width: 280, height: 180)
        .interactiveDismissDisabled()
    }
}
