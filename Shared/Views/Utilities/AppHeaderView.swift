//
//  AppHeaderView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 8/4/21.
//

import SwiftUI

// MARK: - AppHeaderView

struct AppHeaderView: View {
    
    // MARK: Environment
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: Private Properties
    
    private let renderingMode: Image.TemplateRenderingMode
    private let templateColor = Color.white
    
    // MARK: init
    
    init(_ mode: Image.TemplateRenderingMode = .original) {
        renderingMode = mode
    }
    
    // MARK: view
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("Nordic")
                .resizable()
                .renderingMode(colorScheme == .light ? renderingMode : .template)
                .foregroundColor(templateColor)
                .aspectRatio(contentMode: .fit)
                .frame(height: 50)
            
            Divider()
                .foregroundColor(.white)
                .frame(width: 2, height: 60)
                .padding(.leading, 12)
            
            Image("EdgeImpulse")
                .resizable()
                .renderingMode(colorScheme == .light ? renderingMode : .template)
                .foregroundColor(templateColor)
                .aspectRatio(contentMode: .fit)
                .frame(height: 90)
        }
    }
}
