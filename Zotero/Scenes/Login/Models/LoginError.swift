//
//  LoginError.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum LoginError: Error, Identifiable {
    case invalidUsername
    case invalidPassword
    case loginFailed

    var id: LoginError {
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
