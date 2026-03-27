//
//  LoginState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct LoginState: ViewModelState {
    enum SessionStatus {
        case creating
        case checking
        case cancelling
        case completed
        case cancelled
    }

    var sessionStatus: SessionStatus?
    var sessionToken: String?
    var loginURL: URL?
    var isLoading: Bool
    var shouldDismiss: Bool
    var error: LoginError?

    init() {
        sessionStatus = nil
        sessionToken = nil
        loginURL = nil
        isLoading = true
        shouldDismiss = false
        error = nil
    }

    mutating func cleanup() {
        error = nil
        shouldDismiss = false
    }
}
