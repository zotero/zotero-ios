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
    enum Operation {
        case login
        case createSession
        case checkSession
        case cancelSession
    }

    typealias Action = LoginAction
    typealias State = LoginState

    private let apiClient: ApiClient
    private let sessionController: SessionController
    private let webSocketController: LoginSessionWebSocketController
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let disposeBag: DisposeBag
    private let pollingDisposable: SerialDisposable
    private let loginSocketMessageDisposable: SerialDisposable

    init(apiClient: ApiClient, sessionController: SessionController) {
        self.apiClient = apiClient
        self.sessionController = sessionController
        self.webSocketController = LoginSessionWebSocketController()
        scheduler = ConcurrentDispatchQueueScheduler(qos: .userInitiated)
        disposeBag = DisposeBag()
        pollingDisposable = SerialDisposable()
        loginSocketMessageDisposable = SerialDisposable()
    }

    func process(action: LoginAction, in viewModel: ViewModel<LoginActionHandler>) {
        switch action {
        case .login:
            login(in: viewModel)

        case .cancelLoginSessionIfNeeded:
            stopSessionMonitoring(for: viewModel.state.sessionToken)
            cancelLoginSessionIfNeeded(in: viewModel)

        case .setError(let error):
            update(viewModel: viewModel) { state in
                state.error = error
            }

        case .setUsername(let value):
            update(viewModel: viewModel) { state in
                state.username = value
            }

        case .setPassword(let value):
            update(viewModel: viewModel) { state in
                state.password = value
            }
        }
    }

    private func login(in viewModel: ViewModel<LoginActionHandler>) {
        switch viewModel.state.kind {
        case .password:
            loginWithPassword(in: viewModel)

        case .session:
            loginWithSession(in: viewModel)
        }
    }

    private func loginWithPassword(in viewModel: ViewModel<LoginActionHandler>) {
        if let error = isValid(username: viewModel.state.username, password: viewModel.state.password) {
            update(viewModel: viewModel) { state in
                state.error = error
            }
            return
        }

        update(viewModel: viewModel) { state in
            state.sessionStatus = nil
            state.sessionToken = nil
            state.loginURL = nil
            state.isLoading = true
        }

        let request = LoginRequest(username: viewModel.state.username, password: viewModel.state.password)
        apiClient.send(request: request)
            .observe(on: scheduler)
            .flatMap { response, _ -> Single<(Int, String, String, String)> in
                return Single.just((response.userId, response.name, response.displayName, response.key))
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { userId, username, displayName, token in
                sessionController.register(userId: userId, username: username, displayName: displayName, apiToken: token)
            }, onFailure: { [weak viewModel] error in
                DDLogError("LoginActionHandler: could not log in - \(error)")
                guard let viewModel else { return }
                update(viewModel: viewModel, action: { state in
                    state.error = loginError(from: error, for: .login)
                    state.isLoading = false
                })
            })
            .disposed(by: disposeBag)

        func isValid(username: String, password: String) -> LoginError? {
            if username.isEmpty {
                return .invalidUsername
            } else if password.isEmpty {
                return .invalidPassword
            }
            return nil
        }
    }

    private func loginWithSession(in viewModel: ViewModel<LoginActionHandler>) {
        guard viewModel.state.sessionStatus == .none else { return }
        update(viewModel: viewModel) { state in
            state.sessionStatus = .creating
            state.sessionToken = nil
            state.loginURL = nil
            state.isLoading = true
        }

        let request = CreateLoginSessionRequest()
        apiClient.send(request: request)
            .observe(on: scheduler)
            .flatMap { response, _ -> Single<(String, URL)> in
                return Single.just((response.sessionToken, response.loginURL))
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak viewModel] sessionToken, loginURL in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.sessionStatus = .checking
                    state.sessionToken = sessionToken
                    state.loginURL = loginURL
                }
                startStreaming(token: sessionToken, in: viewModel)
                startSessionPolling(with: sessionToken, in: viewModel)
            }, onFailure: { [weak viewModel] error in
                DDLogError("LoginActionHandler: could not create login session - \(error)")
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.sessionStatus = nil
                    state.error = loginError(from: error, for: .createSession)
                    state.isLoading = false
                }
            })
            .disposed(by: disposeBag)
    }

    private func startStreaming(token: String, in viewModel: ViewModel<LoginActionHandler>) {
        let topic = LoginSessionWebSocketController.topic(for: token)
        let messageDisposable = webSocketController.loginObservable
            .observe(on: scheduler)
            .filter({ $0.topic == topic })
            .take(1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak viewModel] response in
                guard let viewModel, viewModel.state.sessionStatus == .checking else { return }
                update(viewModel: viewModel) { state in
                    state.sessionStatus = .completed
                }
                stopSessionMonitoring(for: token)
                sessionController.register(userId: response.userId, username: response.username, displayName: "", apiToken: response.apiKey)
            })

        loginSocketMessageDisposable.disposable = messageDisposable
        webSocketController.connect(sessionToken: token)
    }

    private func startSessionPolling(with token: String, in viewModel: ViewModel<LoginActionHandler>) {
        let statusRequests: Observable<(CheckLoginSessionResponse, HTTPURLResponse)> = Observable<Int>
            .interval(.seconds(3), scheduler: MainScheduler.instance)
            .flatMapLatest { _ in
                apiClient.send(request: CheckLoginSessionRequest(token: token))
                    .asObservable()
            }

        let timeout: Observable<(CheckLoginSessionResponse, HTTPURLResponse)> = Observable<Int>
            .timer(.seconds(10 * 60), scheduler: MainScheduler.instance)
            .flatMap { _ in
                Observable.error(LoginError.sessionTimedOut)
            }

        let disposable = Observable<(CheckLoginSessionResponse, HTTPURLResponse)>
            .merge(statusRequests, timeout)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak viewModel] response, _ in
                guard let viewModel else { return }
                switch response.status {
                case .pending:
                    break

                case .completed(let apiKey, let userId, let username):
                    if viewModel.state.sessionStatus == .checking {
                        update(viewModel: viewModel) { state in
                            state.sessionStatus = .completed
                        }
                        stopSessionMonitoring(for: token)
                        sessionController.register(userId: userId, username: username, displayName: "", apiToken: apiKey)
                    }

                case .cancelled:
                    update(viewModel: viewModel) { state in
                        state.sessionStatus = .cancelled
                        state.shouldDismiss = true
                    }
                    stopSessionMonitoring(for: token)
                }
            }, onError: { [weak viewModel] error in
                DDLogError("LoginActionHandler: could not poll login session - \(error)")
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.sessionStatus = nil
                    state.error = loginError(from: error, for: .checkSession)
                    state.isLoading = false
                }
                stopSessionMonitoring(for: token)
            })

        pollingDisposable.disposable = disposable
    }

    private func stopSessionMonitoring(for token: String?) {
        pollingDisposable.disposable = Disposables.create()
        loginSocketMessageDisposable.disposable = Disposables.create()

        webSocketController.disconnect(sessionToken: token)
    }

    private func cancelLoginSessionIfNeeded(in viewModel: ViewModel<LoginActionHandler>) {
        guard viewModel.state.sessionStatus == .checking else { return }
        guard let token = viewModel.state.sessionToken else {
            update(viewModel: viewModel) { state in
                state.sessionStatus = nil
            }
            return
        }
        update(viewModel: viewModel) { state in
            state.sessionStatus = .cancelling
        }
        apiClient.send(request: CancelLoginSessionRequest(token: token))
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak viewModel] _ in
                DDLogInfo("LoginActionHandler: cancelled session")
                guard let viewModel else { return }
                update(viewModel: viewModel, action: { state in
                    state.sessionStatus = .cancelled
                })
            }, onFailure: { [weak viewModel] error in
                DDLogWarn("LoginActionHandler: could not cancel session - \(loginError(from: error, for: .cancelSession))")
                guard let viewModel else { return }
                update(viewModel: viewModel, action: { state in
                    state.sessionStatus = .cancelled
                })
            })
            .disposed(by: disposeBag)
    }

    private func loginError(from error: Error, for operation: Operation) -> LoginError {
        if let afError = error as? AFResponseError {
            switch afError.error {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code):
                    switch operation {
                    case .login:
                        return code == 403 ? .loginFailed : .serverError(afError.response)

                    case .createSession, .checkSession, .cancelSession:
                        return .serverError(afError.response)
                    }

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
