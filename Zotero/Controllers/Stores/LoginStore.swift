//
//  LoginStore.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RxSwift

class LoginStore: ObservableObject {

    enum Error: Swift.Error, Identifiable {
        case invalidUsername
        case invalidPassword
        case loginFailed

        var id: Error {
            return self
        }

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

    struct State {
        var username: String
        var password: String
        var isLoading: Bool
        var error: Error?
    }

    private let apiClient: ApiClient
    private let secureStorage: SecureStorage
    private let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    @Published var state: State

    init(apiClient: ApiClient, secureStorage: SecureStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.dbStorage = dbStorage
        self.disposeBag = DisposeBag()
        self.state = State(username: "", password: "",
                           isLoading: false, error: nil)
    }

    private func isValid(username: String, password: String) -> Bool {
        if username.isEmpty {
            self.state.error = .invalidUsername
            return false
        }

        if password.isEmpty {
            self.state.error = .invalidPassword
            return false
        }

        return true
    }

    func login() {
        guard self.isValid(username: self.state.username, password: self.state.password) else { return }

        self.state.isLoading = true

        let request = LoginRequest(username: self.state.username, password: self.state.password)
        self.apiClient.send(request: request)
                      .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                      .flatMap { (response, _) -> Single<(Int, String)> in
                          Defaults.shared.username = response.name
                          Defaults.shared.userId = response.userId

                          do {
                              try self.dbStorage.createCoordinator().perform(request: InitializeCustomLibrariesDbRequest())
                              return Single.just((response.userId, response.key))
                          } catch let error {
                              return Single.error(error)
                          }
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onSuccess: { (userId, token) in
                          self.secureStorage.apiToken = token
                          self.apiClient.set(authToken: token)
                          NotificationCenter.default.post(name: .sessionChanged, object: userId)
                      }, onError: { error in
                          DDLogError("LoginStore: could not log in - \(error)")
                          self.state.error = .loginFailed
                          self.state.isLoading = false
                      })
                      .disposed(by: self.disposeBag)
    }
}
