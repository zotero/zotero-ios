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

    weak var coordinatorDelegate: AppLoginCoordinatorDelegate?

    var body: some View {
        VStack(spacing: self.spacing) {
            // Navigation bar
            ZStack {
                HStack {
                    Button(action: {
                        self.coordinatorDelegate?.dismiss()
                    }, label: {
                        Text(L10n.cancel)
                    })
                    Spacer()
                }

                Image(uiImage: Asset.Images.Login.logo.image)
            }
            .frame(maxWidth: .infinity, minHeight: self.navbarHeight, maxHeight: self.navbarHeight)

            // Fields
            VStack(spacing: 0) {
                VStack {
                    Spacer()
                    TextField(L10n.Login.username, text: self.viewModel.binding(keyPath: \.username, action: { .setUsername($0) }))
                        .autocapitalization(.none)
                    Spacer()
                    Divider()
                }
                .frame(height: 48)
                VStack {
                    Spacer()
                    SecureField(L10n.Login.password, text: self.viewModel.binding(keyPath: \.password, action: { .setPassword($0) }))
                    Spacer()
                    Divider()
                }
                .frame(height: 48)
            }

            // Buttons
            VStack(spacing: 0) {
                Button(action: {
                    guard !self.viewModel.state.isLoading else { return }
                    self.viewModel.process(action: .login)
                }, label: {
                    if self.viewModel.state.isLoading {
                        ActivityIndicatorView(style: .medium, color: .white, isAnimating: .constant(true))
                    } else {
                        Text(L10n.Onboarding.signIn)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                })
                .frame(maxWidth: .infinity, minHeight: 45, maxHeight: 45)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                )

                if UIDevice.current.userInterfaceIdiom == .pad {
                    Spacer()
                }

                Button(action: {
                    // TODO: - show forgot password
                }, label: {
                    Text(L10n.Login.forgotPassword)
                        .font(.system(size: 12))
                        .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
                })
                .frame(maxWidth: .infinity, minHeight: 45, maxHeight: 45)
            }

            if UIDevice.current.userInterfaceIdiom == .phone {
                Spacer()
            }
        }
        .padding(.horizontal, self.horizontalPadding)
        .padding(EdgeInsets(top: 0,
                            leading: 0,
                            bottom: UIDevice.current.userInterfaceIdiom == .pad ? self.spacing : 0,
                            trailing: 0))
        .alert(item: self.self.viewModel.binding(keyPath: \.error, action: { .setError($0) })) { error in
            Alert(title: Text(L10n.error),
                  message: Text(error.localizedDescription),
                  dismissButton: .cancel())
        }
    }

    private var spacing: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 35
        } else {
            return 24
        }
    }
    
    private var navbarHeight: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 56
        } else {
            return 44
        }
    }

    private var horizontalPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 20
        } else {
            return 16
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let state = LoginState(username: "", password: "", isLoading: true, error: nil)
        let handler = LoginActionHandler(apiClient: controllers.apiClient, sessionController: controllers.sessionController)
        return LoginView(coordinatorDelegate: nil)
                    .environmentObject(ViewModel(initialState: state, handler: handler))
    }
}
