//
//  LoginView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var viewModel: ViewModel<LoginActionHandler>

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 20) {
                VStack {
                    TextField(L10n.Login.username, text: self.viewModel.binding(keyPath: \.username, action: { .setUsername($0) }))
                        .autocapitalization(.none)
                        .padding([.horizontal, .top])
                    Divider()
                }

                VStack {
                    SecureField(L10n.Login.password, text: self.viewModel.binding(keyPath: \.password, action: { .setPassword($0) }))
                        .autocapitalization(.none)
                        .padding([.horizontal, .top])
                    Divider()
                }

                Button(action: {
                    self.viewModel.process(action: .login)
                }) {
                    OnboardingButton(title: L10n.Onboarding.signIn,
                                     width: proxy.size.width,
                                     isLoading: self.viewModel.state.isLoading)
                }
                .disabled(self.viewModel.state.isLoading)
            }
        }
        .padding()
        .alert(item: self.self.viewModel.binding(keyPath: \.error, action: { .setError($0) })) { error in
            Alert(title: Text(L10n.error),
                  message: Text(error.localizedDescription),
                  dismissButton: .cancel())
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = LoginState(username: "", password: "", isLoading: true, error: nil)
        let handler = LoginActionHandler(apiClient: controllers.apiClient, sessionController: controllers.sessionController)
        return LoginView().environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
