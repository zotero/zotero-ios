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
        }
    }

    private func login(in viewModel: ViewModel<LoginActionHandler>) {
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
                    state.loginURL = loginURL.appendingQueryItem(name: "app", value: "1") ?? loginURL
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
