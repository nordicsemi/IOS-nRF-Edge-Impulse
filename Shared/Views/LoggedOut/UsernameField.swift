//
//  UsernameField.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 8/4/21.
//

import SwiftUI
import iOS_Common_Libraries

// MARK: - UsernameField

struct UsernameField: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: Private Properties
    
    private var username: Binding<String>
    private var enabled: Bool
    
    // MARK: init
    
    init(_ binding: Binding<String>, enabled: Bool) {
        self.username = binding
        self.enabled = enabled
    }
    
    // MARK: view
    
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Image(systemName: "person.fill")
                .frame(size: .StandardImageSize)
                .accentColor(.nordicDarkGrey)
            
            #if os(iOS)
            TextField("Username or E-Mail", text: username)
                .foregroundColor(.primary)
                .keyboardType(.emailAddress)
                .roundedTextFieldStyle()
            #else
            GroupBox {
                TextField("Username or E-Mail", text: username)
                    .foregroundColor(.primary)
            }
            #endif
        }
        .textContentType(.username)
        .disableAllAutocorrections()
        .disabled(!enabled)
    }
}

// MARK: - Preview

#if DEBUG
struct UsernameField_Previews: PreviewProvider {
    
    @State static var emptyUsername: String = ""
    @State static var username: String = "taylor.swift"
    
    static var previews: some View {
        Group {
            UsernameField($emptyUsername, enabled: true)
            UsernameField($username, enabled: true)
            UsernameField($username, enabled: false)
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
