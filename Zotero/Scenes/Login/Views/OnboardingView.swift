//
//  OnboardingView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct OnboardingView: View {
    private let spacing: CGFloat = 20

    @Environment(\.apiClient) private var apiClient: ApiClient
    @Environment(\.sessionController) private var sessionController: SessionController

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                HStack(spacing: self.spacing) {
                    NavigationLink(destination: LoginView().environmentObject(self.loginViewModel)) {
                        OnboardingButton(title: L10n.Login.signIn,
                                         width: (proxy.size.width - self.spacing) / 2.0,
                                         isLoading: false)
                    }

                    NavigationLink(destination: RegisterView()) {
                        OnboardingButton(title: L10n.Login.createAccount,
                                         width: (proxy.size.width - self.spacing) / 2.0,
                                         isLoading: false)
                    }
                }
            }
            .padding()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var loginViewModel: ViewModel<LoginActionHandler> {
        let state = LoginState(username: "", password: "", isLoading: false, error: nil)
        let handler = LoginActionHandler(apiClient: self.apiClient, sessionController: self.sessionController)
        return ViewModel(initialState: state, handler: handler)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
