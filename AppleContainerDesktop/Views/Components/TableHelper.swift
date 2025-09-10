//
//  TableHelper.swift
//  AppleContainerDesktop
//
//  Created by Itsuki on 2025/09/10.
//

import SwiftUI

class TableHelper {
    static func columnHeader(_ title: String) -> Text {
        Text(title).foregroundStyle(.primary).font(.headline).fontWeight(.bold)
    }
    
    static func actionImage(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .padding(.all, 3)
            .frame(width: 16)
    }
}
