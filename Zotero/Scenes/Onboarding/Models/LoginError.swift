//
//  LoginError.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum LoginError: Error {
    case invalidUsername
    case invalidPassword
    case loginFailed
    case serverError(String)
    case unknown(Error)

    var localizedDescription: String {
        switch self {
        case .invalidPassword:
            return L10n.Errors.Login.invalidPassword

        case .invalidUsername:
            return L10n.Errors.Login.invalidUsername

        case .loginFailed:
            return L10n.Errors.Login.invalidCredentials

        case .serverError(let response):
            return response

        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
