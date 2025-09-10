//
//  SearchBox.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/08.
//

import SwiftUI

struct SearchBox: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(text: $text, prompt: Text("Search"), label: {})
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                
        }
        .padding(.all, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(.clear).stroke(.secondary, style: .init(lineWidth: 1)))
    }
}
