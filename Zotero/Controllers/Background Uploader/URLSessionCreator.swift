//
//  URLSessionCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 15.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class URLSessionCreator {
    static func createSession(for identifier: String, delegate: URLSessionDelegate?) -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
