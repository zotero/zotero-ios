//
//  LoginState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct LoginState: ViewModelState {
    enum RequestKind {
        case login
        case createAccount
    }

    enum SessionStatus {
        case creating
        case checking
        case cancelling
        case completed
    }

    var sessionStatus: SessionStatus?
    var sessionToken: String?
    var loginURL: URL?
    var requestKind: RequestKind?
    var isLoading: Bool
    var error: LoginError?

    init() {
        sessionStatus = nil
        sessionToken = nil
        loginURL = nil
        requestKind = nil
        isLoading = false
        error = nil
    }

    mutating func cleanup() {
        error = nil
    }
}
