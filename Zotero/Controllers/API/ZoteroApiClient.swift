//
//  ZoteroApiClient.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import Alamofire

struct ApiConstants {
    static var baseUrlString: String = "https://api.zotero.org/"
    static var version: Int = 3
}

enum ZoteroApiError: Error {
    case unknown
    case jsonDecoding(Error)
}

class ZoteroApiClient: ApiClient {
    private let url: URL
    private let manager: SessionManager

    private var token: String?

    init(baseUrl: String, headers: [String: Any]? = nil) {
        guard let url = URL(string: baseUrl) else {
            fatalError("Incorrect base url provided for ZoteroApiClient")
        }

        self.url = url

        let configuration = URLSessionConfiguration.default
        if let headers = headers {
            configuration.httpAdditionalHeaders = headers
        }
        self.manager = SessionManager(configuration: configuration)
    }

    func set(authToken: String?) {
        self.token = authToken
    }

    func send<Request>(request: Request,
                       completion: @escaping RequestCompletion<Request.Response>) where Request : ApiRequest {  
        let convertible = Convertible(request: request, baseUrl: self.url, token: self.token)
        self.manager.request(convertible).validate().responseData { response in
            if let error = response.error {
                completion(.failure(error))
                return
            }

            if let data = response.data {
                do {
                    let decodedResponse = try JSONDecoder().decode(Request.Response.self, from: data)
                    completion(.success(decodedResponse))
                } catch let error {
                    completion(.failure(ZoteroApiError.jsonDecoding(error)))
                }

                return
            }

            completion(.failure(ZoteroApiError.unknown))
        }
    }
}

fileprivate struct Convertible<Request: ApiRequest> {
    private let url: URL
    private let token: String?
    private let httpMethod: ApiHttpMethod
    private let encoding: ParameterEncoding
    private let parameters: [String: Any]?

    init(request: Request, baseUrl: URL, token: String?) {
        self.url = baseUrl.appendingPathComponent(request.path)
        self.token = token
        self.httpMethod = request.httpMethod
        self.encoding = request.encoding.alamoEncoding
        self.parameters = request.parameters
    }
}

extension Convertible: URLRequestConvertible {
    func asURLRequest() throws -> URLRequest {
        var request = URLRequest(url: self.url)
        request.httpMethod = self.httpMethod.rawValue
        if let token = self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try self.encoding.encode(request as URLRequestConvertible, with: self.parameters)
    }
}

extension ApiParameterEncoding {
    fileprivate var alamoEncoding: ParameterEncoding {
        switch self {
        case .json:
            return JSONEncoding()
        case .url:
            return URLEncoding()
        }
    }
}
