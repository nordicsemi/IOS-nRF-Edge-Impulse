//
//  NativeLoginView.swift
//  nRF-Edge-Impulse
//
//  Created by Dinesh Harjani on 25/2/21.
//

import SwiftUI
import Combine
import iOS_Common_Libraries

struct NativeLoginView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - EnvironmentObject(s)
    
    @EnvironmentObject var appData: AppData
    
    // MARK: - State
    
    @State var username: String = ""
    @State var password: String = ""
    
    @State private var showMFAAlert = false
    @State private var mfaToken: String = ""
    
    @State private var viewState: ViewState = .clean
    @State private var loginCancellable: Cancellable? = nil
    
    // MARK: - FocusedField
    
    @FocusState private var focusedField: Field?
    
    private enum Field: Int, Hashable {
        case username, password
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            
            AppHeaderView()
            
            UsernameField($username, enabled: !isMakingRequest)
                .frame(maxWidth: .maxTextFieldWidth)
                .padding(.horizontal, 16)
                .focused($focusedField, equals: .username)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .password
                }
            
            #if os(iOS)
            HStack(alignment: .lastTextBaseline) {
                Image(systemName: "key.fill")
                    .frame(size: .StandardImageSize)
                    .accentColor(.nordicDarkGrey)
                
                PasswordField(binding: $password, enabled: !isMakingRequest)
                    .foregroundColor(.primary)
                    .roundedTextFieldStyle()
                    .padding(.vertical, 8)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        let parameters = LoginParameters(username: username,
                                                         password: password)
                        attemptLogin(with: parameters)
                    }
            }
            .frame(maxWidth: .maxTextFieldWidth)
            .padding(.horizontal, 16)
            #else
            HStack(alignment: .lastTextBaseline) {
                Image(systemName: "key.fill")
                    .frame(size: .StandardImageSize)
                    .accentColor(.nordicDarkGrey)
                
                GroupBox {
                    PasswordField(binding: $password, enabled: !isMakingRequest)
                        .focused($focusedField, equals: .password)
                }
            }
            .frame(maxWidth: .maxTextFieldWidth)
            .padding(.horizontal, 16)
            #endif
            
            LoginErrorView(viewState: viewState)
            
            LoginButtonView(viewState: viewState, loginDisabled: isLoginButtonDisabled,
                            loginAction: {
                let parameters = LoginParameters(username: username,
                                                 password: password)
                attemptLogin(with: parameters)
            })
            
            SignUpView()
            
            Spacer()
        }
        .textFieldAlert(title: "MFA Token", message: "Type your Authentication Token here", isPresented: $showMFAAlert, text: $mfaToken, onPositiveAction: {
            let parameters = LoginParameters(username: username,
                                             password: password,
                                             totpToken: mfaToken)
            attemptLogin(with: parameters)
        })
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.focusedField = .username
            }
        }
    }
}

// MARK: - Logic

fileprivate extension NativeLoginView {
    
    var isLoginButtonDisabled: Bool {
        !isMakingRequest && (username.isEmpty || password.isEmpty)
    }
    
    var isMakingRequest: Bool {
        switch viewState {
        case .makingRequest:
            return true
        default:
            return false
        }
    }
    
    func attemptLogin(with parameters: LoginParameters) {
        guard let httpRequest = HTTPRequest.login(parameters) else {
            // Show error.
            return
        }
        
        loginCancellable = Network.shared.perform(httpRequest, responseType: LoginResponse.self)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    mfaToken = ""
                    viewState = .error(error.localizedDescription)
                default:
                    break
                }
            }, receiveValue: { loginResponse in
                guard loginResponse.success else {
                    let error = loginResponse.error ?? "Unknown Error"
                    if error.localizedCaseInsensitiveContains("ERR_TOTP_TOKEN") {
                        showMFAAlert = true
                    } else {
                        viewState = .error(error)
                        mfaToken = ""
                    }
                    return
                }
                mfaToken = ""
                appData.apiToken = loginResponse.token
            })
        viewState = .makingRequest
    }
}

// MARK: - ViewState

internal extension NativeLoginView {
    
    enum ViewState {
        case clean
        case makingRequest
        case error(_ message: String)
    }
}
