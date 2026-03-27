//
//  LoginState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct LoginState: ViewModelState {
    enum Kind: Equatable {
        case password
        case session
    }

    enum SessionStatus {
        case creating
        case checking
        case cancelling
        case completed
        case cancelled
    }

    let kind: Kind
    var username: String
    var password: String
    var sessionStatus: SessionStatus?
    var sessionToken: String?
    var loginURL: URL?
    var isLoading: Bool
    var shouldDismiss: Bool
    var error: LoginError?

    init(kind: Kind) {
        self.kind = kind
        username = ""
        password = ""
        sessionStatus = nil
        sessionToken = nil
        loginURL = nil
        isLoading = (kind == .session)
        shouldDismiss = false
        error = nil
    }

    mutating func cleanup() {
        error = nil
        shouldDismiss = false
    }
}
