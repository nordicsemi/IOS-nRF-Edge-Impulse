//
//  DeploymentErrorView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 22/11/21.
//

import SwiftUI

// MARK: - DeploymentErrorView

struct DeploymentErrorView: View {
    
    // MARK: Private
    
    private let error: Error
    
    // MARK: init
    
    init(_ error: Error) {
        self.error = error
    }
    
    // MARK: view
    
    var body: some View {
        Section("Error Description") {
            #if os(macOS)
            Divider()
                .padding(.horizontal)
            #endif
            
            // Align with the StageView items.
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .renderingMode(.template)
                    .foregroundStyle(Color.red)
                    .frame(width: 20, height: 20)
                
                Text(error.localizedDescription)
            }
            .padding(.leading, 2)
        }
    }
}

// MARK: - Preview

#if DEBUG
import iOS_Common_Libraries

struct DeploymentErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FormIniOSListInMacOS {
                DeploymentErrorView(NordicError.testError)
            }
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
