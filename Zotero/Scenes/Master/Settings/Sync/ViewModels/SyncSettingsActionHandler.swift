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

    private unowned let webDavController: WebDavController
    private unowned let sessionController: SessionController
    private let disposeBag: DisposeBag

    init(sessionController: SessionController, webDavController: WebDavController) {
        self.sessionController = sessionController
        self.webDavController = webDavController
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
            self.webDavController.sessionStorage.isEnabled = type == .webDav

        case .setScheme(let scheme):
            self.update(viewModel: viewModel) { state in
                state.scheme = scheme
            }
            self.webDavController.sessionStorage.scheme = scheme

        case .setUrl(let url):
            self.update(viewModel: viewModel) { state in
                state.url = url
            }
            self.webDavController.sessionStorage.url = url

        case .setUsername(let username):
            self.update(viewModel: viewModel) { state in
                state.username = username
            }
            self.webDavController.sessionStorage.username = username

        case .setPassword(let password):
            self.update(viewModel: viewModel) { state in
                state.password = password
            }
            self.webDavController.sessionStorage.password = password

        case .verify:
            self.update(viewModel: viewModel) { state in
                state.isVerifyingWebDav = true
            }

            self.webDavController.checkServer()
                .observe(on: MainScheduler.instance)
                .subscribe(with: viewModel, onSuccess: { viewModel, _ in
                    self.update(viewModel: viewModel) { state in
                        state.isVerifyingWebDav = false
                        state.webDavVerificationResult = .success(())
                    }
                }, onFailure: { viewModel, error in
                    self.update(viewModel: viewModel) { state in
                        state.isVerifyingWebDav = false
                        state.webDavVerificationResult = .failure(error)
                    }
                })
                .disposed(by: self.disposeBag)
        }
    }
}

