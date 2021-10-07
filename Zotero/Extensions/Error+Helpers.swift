//
//  Error+Helpers.swift
//  Zotero
//
//  Created by Michal Rentka on 07.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

extension Error {
    var isInternetConnectionError: Bool {
        return self.alamofireError(process: { $0.isInternetConnectionError }, defaultValue: false)
    }

    var unacceptableStatusCode: Int? {
        return self.alamofireError(process: { $0.unacceptableStatusCode }, defaultValue: nil)
    }

    private func alamofireError<T>(process: (AFError) -> T, defaultValue: T) -> T {
        if let responseError = self as? AFResponseError {
            return process(responseError.error)
        }
        if let error = self as? AFError {
            return process(error)
        }
        return defaultValue
    }
}

extension AFError {
    var isInternetConnectionError: Bool {
        switch self {
        case .sessionTaskFailed(let error):
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet
        case .multipartEncodingFailed, .parameterEncodingFailed, .parameterEncoderFailed, .invalidURL, .createURLRequestFailed, .requestAdaptationFailed, .requestRetryFailed,
             .serverTrustEvaluationFailed, .sessionDeinitialized, .sessionInvalidated, .urlRequestValidationFailed, .responseValidationFailed, .responseSerializationFailed, .createUploadableFailed,
             .downloadedFileMoveFailed, .explicitlyCancelled:
            return false
        }
    }

    var unacceptableStatusCode: Int? {
        switch self {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return code
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
