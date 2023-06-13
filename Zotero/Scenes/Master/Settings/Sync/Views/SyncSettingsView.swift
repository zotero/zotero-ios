//
//  SyncSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

import Alamofire

struct SyncSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section(header: Text(L10n.Settings.Sync.dataSyncing)) {
                Text(self.viewModel.state.account)

                Button {
                    self.coordinatorDelegate?.showLogoutAlert(viewModel: self.viewModel)
                } label: {
                    Text(L10n.Settings.logout)
                        .foregroundColor(.red)
                }
            }

            Section(header: Text(L10n.Settings.Sync.fileSyncing)) {
                self.fileSyncSection
            }

            Section(header: Text(L10n.Settings.Sync.account)) {
                Button {
                    self.coordinatorDelegate?.showWeb(url: URL(string: "https://www.zotero.org/settings/account")!, completion: {
                        self.viewModel.process(action: .recheckKeys)
                    })
                } label: {
                    Text(L10n.Settings.Sync.manageAccount)
                        .foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor)
                }

                Button {
                    self.coordinatorDelegate?.showWeb(url: URL(string: "https://www.zotero.org/settings/deleteaccount")!, completion: {
                        self.viewModel.process(action: .recheckKeys)
                    })
                } label: {
                    Text(L10n.Settings.Sync.deleteAccount)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarTitle(L10n.Settings.Sync.title)
    }

    private var fileSyncSection: some View {
        var view = FileSyncingSection()
        view.coordinatorDelegate = self.coordinatorDelegate
        return view
    }
}

struct FileSyncingSection: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Picker(L10n.Settings.Sync.fileSyncingTypeMessage, selection: self.viewModel.binding(get: \.fileSyncType, action: { .setFileSyncType($0) })) {
            Text("Zotero").tag(SyncSettingsState.FileSyncType.zotero)
            Text("WebDAV").tag(SyncSettingsState.FileSyncType.webDav)
        }
        .disabled(self.viewModel.state.updatingFileSyncType)

        if self.viewModel.state.fileSyncType == .webDav {
            self.webDavSettings
        }
    }

    private var webDavSettings: some View {
        var view = WebDavSettings()
        view.coordinatorDelegate = self.coordinatorDelegate
        return view
    }
}

struct WebDavSettings: View {
    @EnvironmentObject var viewModel: ViewModel<SyncSettingsActionHandler>

    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        HStack(spacing: 6) {
            Button(self.viewModel.state.scheme.rawValue + "://") {
                self.coordinatorDelegate?.showSchemePicker(viewModel: self.viewModel)
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(Color(UIColor.label))

            TextField("URL", text: self.viewModel.binding(get: \.url, action: { .setUrl($0) }))
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Text("/zotero/")
        }

        TextField(L10n.Settings.Sync.username, text: self.viewModel.binding(get: \.username, action: { .setUsername($0) }))
            .autocapitalization(.none)
            .disableAutocorrection(true)

        SecureField(L10n.Settings.Sync.password, text: self.viewModel.binding(get: \.password, action: { .setPassword($0) }))
            .autocapitalization(.none)
            .disableAutocorrection(true)

        if self.viewModel.state.isVerifyingWebDav {
            HStack {
                ActivityIndicatorView(style: .medium, isAnimating: .constant(true))

                Spacer()

                Button(L10n.cancel) {
                    self.viewModel.process(action: .cancelVerification)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor)
            }
        } else {
            HStack {
                Button(L10n.Settings.Sync.verify) {
                    self.viewModel.process(action: .verify)
                }
                .foregroundColor(self.canVerifyServer ? Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor : .gray)
                .disabled(!self.canVerifyServer)

                if let result = self.viewModel.state.webDavVerificationResult, case .success = result {
                    Spacer()

                    HStack {
                        Text(L10n.Settings.Sync.verified)

                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
            }
        }

        if case .failure(let error) = self.viewModel.state.webDavVerificationResult {
            Text(self.errorMessage(for: error))
                .foregroundColor(.red)
        }
    }

    private var canVerifyServer: Bool {
        return !self.viewModel.state.url.isEmpty && !self.viewModel.state.username.isEmpty && !self.viewModel.state.password.isEmpty
    }

    private func errorMessage(for error: Error) -> String {
        if let error = error as? WebDavError.Verification {
            return error.message
        }

        if let responseError = error as? AFResponseError, let message = self.errorMessage(for: responseError.error) {
            return message
        }
        if let error = error as? AFError, let message = self.errorMessage(for: error) {
            return message
        }

        return error.localizedDescription
    }

    private func errorMessage(for error: AFError) -> String? {
        switch error {
        case .sessionTaskFailed(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet:
                    return L10n.Errors.Settings.Webdav.internetConnection

                case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                    return L10n.Errors.Settings.Webdav.hostNotFound
                default: break
                }
            }

        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let statusCode):
                switch statusCode {
                case 401:
                    return L10n.Errors.Settings.Webdav.unauthorized

                case 403:
                    return L10n.Errors.Settings.Webdav.forbidden
                default: return nil
                }

            default: break
            }

        default: break
        }

        return L10n.Errors.Settings.Webdav.hostNotFound
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        return SyncSettingsView()
    }
}
