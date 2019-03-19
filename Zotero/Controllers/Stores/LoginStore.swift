//
//  LoginStore.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift

class LoginStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreError: Error, Equatable {
        case invalidUsername
        case invalidPassword
        case loginFailed

        var localizedDescription: String {
            switch self {
            case .invalidPassword:
                return "Invalid password"
            case .invalidUsername:
                return "Invalid username"
            case .loginFailed:
                return "Could not log in"
            }
        }
    }

    enum StoreAction {
        case login(username: String, password: String)
        case hideError
    }

    enum StoreState {
        case error(StoreError)
        case loading
        case input
    }

    private let apiClient: ApiClient
    private let secureStorage: SecureStorage
    private let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    var updater: StoreStateUpdater<StoreState>

    init(apiClient: ApiClient, secureStorage: SecureStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.dbStorage = dbStorage
        self.disposeBag = DisposeBag()
        self.updater = StoreStateUpdater(initialState: .input)
    }

    func handle(action: StoreAction) {
        switch action {
        case .hideError:
            self.updater.updateState { newState in
                newState = .input
            }

        case .login(let username, let password):
            self.handleLogin(username: username, password: password)
        }
    }

    private func isValid(username: String, password: String) -> Bool {
        if username.isEmpty {
            self.updater.updateState { newState in
                newState = .error(StoreError.invalidUsername)
            }
            return false
        }

        if password.isEmpty {
            self.updater.updateState { newState in
                newState = .error(StoreError.invalidPassword)
            }
            return false
        }

        return true
    }

    private func handleLogin(username: String, password: String) {
        guard self.isValid(username: username, password: password) else { return }

        self.updater.updateState { newState in
            newState = .loading
        }

        let request = LoginRequest(username: username, password: password)
        self.apiClient.send(request: request)
                      .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                      .flatMap { response -> Single<(Int, String)> in
                          do {
                              let request = StoreUserDbRequest(loginResponse: response.0)
                              try self.dbStorage.createCoordinator().perform(request: request)
                              return Single.just((response.0.userId, response.0.key))
                          } catch let error {
                              return Single.error(error)
                          }
                      }
                      .subscribe(onSuccess: { data in
                          self.secureStorage.apiToken = data.1
                          self.apiClient.set(authToken: data.1)
                          NotificationCenter.default.post(name: .sessionChanged, object: data.0)
                      }, onError: { error in
                          DDLogError("LoginStore: could not log in - \(error)")
                          self.updater.updateState(action: { newState in
                              newState = .error(.loginFailed)
                          })
                      })
                      .disposed(by: self.disposeBag)
    }
}

extension LoginStore.StoreState: Equatable {
    static func == (lhs: LoginStore.StoreState, rhs: LoginStore.StoreState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.input, .input):
            return true
        case (.error(let lError), .error(let rError)):
            return lError == rError
        default:
            return false
        }
    }
}
