//
//  SyncSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct SyncSettingsActionHandler: ViewModelActionHandler {
    typealias Action = SyncSettingsAction
    typealias State = SyncSettingsState

    private unowned let sessionController: SessionController
    private unowned let secureStorage: SecureStorage
    private let disposeBag: DisposeBag

    init(sessionController: SessionController, secureStorage: SecureStorage) {
        self.sessionController = sessionController
        self.secureStorage = secureStorage
        self.disposeBag = DisposeBag()
    }

    func process(action: SyncSettingsAction, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        switch action {
        case .logout:
            self.sessionController.reset()

        case .setFileSyncType(let type):
            self.update(viewModel: viewModel) { state in
                state.fileSyncType = type
            }
            Defaults.shared.webDavEnabled = type == .webDav

        case .setScheme(let scheme):
            self.update(viewModel: viewModel) { state in
                state.scheme = scheme
            }
            Defaults.shared.webDavScheme = scheme

        case .setUrl(let url):
            self.update(viewModel: viewModel) { state in
                state.url = url
            }
            Defaults.shared.webDavUrl = url

        case .setUsername(let username):
            self.update(viewModel: viewModel) { state in
                state.username = username
            }
            Defaults.shared.webDavUsername = username

        case .setPassword(let password):
            self.update(viewModel: viewModel) { state in
                state.password = password
            }
            self.secureStorage.webDavPassword = password.isEmpty ? nil : password

        case .verify:
            break
        }
    }
}

