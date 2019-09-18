//
//  LoginView.swift
//  Zotero
//
//  Created by Michal Rentka on 17/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private(set) var store: LoginStore

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 20) {
                VStack {
                    TextField("Username", text: self.$store.state.username)
                        .padding([.horizontal, .top])
                    Divider()
                }

                VStack {
                    SecureField("Password", text: self.$store.state.password)
                        .padding([.horizontal, .top])
                    Divider()
                }

                Button(action: self.store.login) {
                    OnboardingButton(title: "Sign in",
                                     width: proxy.size.width,
                                     isLoading: self.store.state.isLoading)
                }
                .disabled(self.store.state.isLoading)
            }
        }
        .padding()
        .alert(item: self.$store.state.error) { error in
            Alert(title: Text("Error"),
                  message: Text(error.localizedDescription),
                  dismissButton: .cancel())
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let store = LoginStore(apiClient: controllers.apiClient,
                               secureStorage: controllers.secureStorage,
                               dbStorage: controllers.dbStorage)
        store.state.isLoading = true
        return LoginView(store: store)
    }
}
