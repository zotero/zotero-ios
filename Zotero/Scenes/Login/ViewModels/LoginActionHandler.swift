//
//  LoginActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift

struct LoginActionHandler: ViewModelActionHandler {
    typealias Action = LoginAction
    typealias State = LoginState

    private let apiClient: ApiClient
    private let sessionController: SessionController
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, sessionController: SessionController) {
        self.apiClient = apiClient
        self.sessionController = sessionController
        self.scheduler = ConcurrentDispatchQueueScheduler(qos: .userInitiated)
        self.disposeBag = DisposeBag()
    }

    func process(action: LoginAction, in viewModel: ViewModel<LoginActionHandler>) {
        switch action {
        case .login:
            self.login(in: viewModel)

        case .setError(let error):
            self.update(viewModel: viewModel) { state in
                state.error = error
            }

        case .setUsername(let value):
            self.update(viewModel: viewModel) { state in
                state.username = value
            }

        case .setPassword(let value):
            self.update(viewModel: viewModel) { state in
                state.password = value
            }
        }
    }

    private func isValid(username: String, password: String) -> LoginError? {
        if username.isEmpty {
            return .invalidUsername
        }

        if password.isEmpty {
            return .invalidPassword
        }

        return nil
    }

    private func login(in viewModel: ViewModel<LoginActionHandler>) {
        if let error = self.isValid(username: viewModel.state.username, password: viewModel.state.password) {
            self.update(viewModel: viewModel) { state in
                state.error = error
            }
            return
        }

        self.update(viewModel: viewModel) { state in
            state.isLoading = true
        }

        let request = LoginRequest(username: viewModel.state.username, password: viewModel.state.password)
        self.apiClient.send(request: request)
                      .observeOn(self.scheduler)
                      .flatMap { (response, _) -> Single<(Int, String, String)> in
                          return Single.just((response.userId, response.name, response.key))
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onSuccess: { userId, username, token in
                          self.sessionController.register(userId: userId, username: username, apiToken: token)
                      }, onError: { [weak viewModel] error in
                          DDLogError("LoginStore: could not log in - \(error)")
                          guard let viewModel = viewModel else { return }
                          self.update(viewModel: viewModel, action: { state in
                              state.error = .loginFailed
                              state.isLoading = false
                          })
                      })
                      .disposed(by: self.disposeBag)
    }
}
