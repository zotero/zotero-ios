//
//  LoginActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
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
                      .observe(on: self.scheduler)
                      .flatMap { response, _ -> Single<(Int, String, String, String)> in
                          return Single.just((response.userId, response.name, response.displayName, response.key))
                      }
                      .observe(on: MainScheduler.instance)
                      .subscribe(onSuccess: { userId, username, displayName, token in
                          self.sessionController.register(userId: userId, username: username, displayName: displayName, apiToken: token)
                      }, onFailure: { [weak viewModel] error in
                          DDLogError("LoginStore: could not log in - \(error)")
                          guard let viewModel = viewModel else { return }
                          self.update(viewModel: viewModel, action: { state in
                              state.error = self.loginError(from: error)
                              state.isLoading = false
                          })
                      })
                      .disposed(by: self.disposeBag)
    }

    private func loginError(from error: Error) -> LoginError {
        if let afError = error as? AFResponseError {
            switch afError.error {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code):
                    return code == 403 ? .loginFailed : .serverError(afError.response)

                default:
                    return afError.response.isEmpty ? .unknown(error) : .serverError(afError.response)
                }

            case .sessionTaskFailed(let error):
                return .serverError(error.localizedDescription)

            default:
                return afError.response.isEmpty ? .unknown(error) : .serverError(afError.response)
            }
        } else {
            return .unknown(error)
        }
    }
}
