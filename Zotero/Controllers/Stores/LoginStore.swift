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
    private let disposeBag: DisposeBag

    @Published var state: State

    init(apiClient: ApiClient) {
        self.apiClient = apiClient
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
                      .flatMap { (response, _) -> Single<(Int, String, String)> in
                          return Single.just((response.userId, response.name, response.key))
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onSuccess: { (userId, username, token) in
                          NotificationCenter.default.post(name: .sessionChanged, object: (userId, username, token))
                      }, onError: { error in
                          DDLogError("LoginStore: could not log in - \(error)")
                          self.state.error = .loginFailed
                          self.state.isLoading = false
                      })
                      .disposed(by: self.disposeBag)
    }
}
