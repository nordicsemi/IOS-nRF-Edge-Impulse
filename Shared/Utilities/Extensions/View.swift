//
//  View.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 8/3/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - View

extension View {
    
    // MARK: - NavBar
    
    @ViewBuilder
    func toolbarPrincipalImage(_ image: Image) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .principal) {
                image
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(size: .ToolbarImageSize)
                    .aspectRatio(contentMode: .fit)
            }
        }
        #else
        self
        #endif
    }
    
    // MARK: - View + HUD
    func hud<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            if isPresented.wrappedValue {
                HUD(content: content)
                    .transition(
                        AnyTransition.move(edge: .top).combined(with: .opacity)
                    )
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                isPresented.wrappedValue = false
                            }
                        }
                    }
                    .zIndex(1)
            }
        }
    }
}
