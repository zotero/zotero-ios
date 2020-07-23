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
            LoginViewHeader(coordinatorDelegate: self.coordinatorDelegate)
            VStack(spacing: 0) {
                LoginViewTextField(type: .username)
                LoginViewTextField(type: .password)
            }
            LoginViewButtons(coordinatorDelegate: self.coordinatorDelegate)
            if UIDevice.current.userInterfaceIdiom == .phone {
                Spacer()
            }
        }
        .padding(.horizontal, self.horizontalPadding)
        .padding(.bottom, (UIDevice.current.userInterfaceIdiom == .pad ? self.spacing : 0))
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

    private var horizontalPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 20
        } else {
            return 16
        }
    }
}

fileprivate struct LoginViewHeader: View {
    weak var coordinatorDelegate: AppLoginCoordinatorDelegate?

    var body: some View {
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
        .frame(maxWidth: .infinity, minHeight: self.height, maxHeight: self.height)
    }

    private var height: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 56
        } else {
            return 44
        }
    }
}

fileprivate struct LoginViewTextField: View {
    @EnvironmentObject var viewModel: ViewModel<LoginActionHandler>

    let type: LoginState.TextField

    var body: some View {
        VStack {
            Spacer()
            SelectableTextField(placeholder: self.placeholder,
                                text: self.textBinding,
                                secure: (self.type == .password),
                                autocapitalizationType: .none,
                                returnKeyType: (self.type == .password ? .done : .next),
                                isFirstResponder: self.firstResponderBinding,
                                didTapDone: self.doneBinding)
            Spacer()
            Divider()
        }
        .frame(height: 48)
    }

    var placeholder: String {
        switch self.type {
        case .username: return L10n.Login.username
        case .password: return L10n.Login.password
        }
    }

    var textBinding: Binding<String> {
        switch self.type {
        case .username: return self.viewModel.binding(keyPath: \.username, action: { .setUsername($0) })
        case .password: return self.viewModel.binding(keyPath: \.password, action: { .setPassword($0) })
        }
    }

    var firstResponderBinding: Binding<Bool> {
        return self.viewModel.binding(get: {
                                          $0.selectedTextField == self.type
                                      },
                                      action: { value in
                                         // Ignore when `isFirstResponder` is set to `false` because it would create unnecessary reloads and setting
                                         // it to `true` will set correct selected field anyway.
                                          guard value else { return nil }
                                          return .setSelectedTextField(self.type)
                                      })
    }

    var doneBinding: Binding<Bool> {
        // This is a workaround because we can't bind this view to `SelectableTextField` done button. So there is a `didTapDone`
        // binding of type `Binding<Bool>` which is set to `true` by tapping on done button and it's set to `false` on each SwiftUI update.
        return self.viewModel.binding(get: { _ in false }, action: { value in
            // Only `true` value is set to user tap and action needs to be created for it. `false` value is set automatically and needs to be ignored.
            guard value else { return nil }
            return self.type == .password ? .login : .setSelectedTextField(.password)
        })
    }
}

fileprivate struct LoginViewButtons: View {
    @EnvironmentObject var viewModel: ViewModel<LoginActionHandler>
    weak var coordinatorDelegate: AppLoginCoordinatorDelegate?

    var body: some View {
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
                self.coordinatorDelegate?.showForgotPassword()
            }, label: {
                Text(L10n.Login.forgotPassword)
                    .font(.system(size: 12))
                    .foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor)
            })
            .frame(maxWidth: .infinity, minHeight: 45, maxHeight: 45)
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        let controllers = Controllers()
        let handler = LoginActionHandler(apiClient: controllers.apiClient, sessionController: controllers.sessionController)
        return LoginView(coordinatorDelegate: nil)
                    .environmentObject(ViewModel(initialState: LoginState(), handler: handler))
    }
}
