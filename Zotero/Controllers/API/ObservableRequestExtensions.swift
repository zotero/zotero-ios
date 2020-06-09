//
//  ObservableRequestExtensions.swift
//  Zotero
//
//  Created by Michal Rentka on 10/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
import RxAlamofire
import RxSwift

struct AFResponseError: Error {
    let error: AFError
    let headers: [AnyHashable : Any]?
    let response: String
}

fileprivate enum RetryDelay {
    case constant(Double)
    case progressive(initial: Double, multiplier: Double, maxDelay: Double)
}

fileprivate struct ApiLogger {
    static func log(request: ApiRequest, url: URL?) {
        DDLogInfo("--- API request '\(type(of: request))' ---")
        DDLogInfo("(\(request.httpMethod.rawValue)) \(url?.absoluteString ?? "")")
        if request.httpMethod != .get, let params = request.parameters {
            DDLogInfo("\(request.redact(parameters: params))")
        }
    }

    static func log(response: (HTTPURLResponse, Data)?, error: Error?, for request: ApiRequest) {
        if let data = response?.1,
           let string = String(data: data, encoding: .utf8) {
            DDLogInfo("(\(response?.0.statusCode ?? -1)) \(request.redact(response: string))")
        } else if let error = error {
            DDLogInfo("\(error)")
        }
    }
}

extension RetryDelay {
    func seconds(for attempt: Int) -> Double {
        switch self {
        case .constant(let time):
            return time
        case .progressive(let initial, let multiplier, let maxDelay):
            let delay = attempt == 1 ? initial : (initial * pow(multiplier, Double(attempt - 1)))
            return min(maxDelay, delay)
        }
    }
}

extension ObservableType where Element == (HTTPURLResponse, Data) {
    func retryIfNeeded() -> Observable<Element> {
        return self.retry(maxAttemptCount: 10,
                          retryDelay: { error -> RetryDelay? in
            guard let responseError = error as? AFResponseError else { return nil }
            switch responseError.error {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code):
                    if code == 429 || (code >= 500 && code <= 599) {
                        let delay: RetryDelay
                        if let retryHeader = responseError.headers?["Retry-After"] as? Double {
                            delay = .constant(retryHeader)
                        } else {
                            delay = .progressive(initial: 2.5, multiplier: 2, maxDelay: 3600)
                        }
                        return delay
                    }
                    return nil
                default: return nil
                }
            default: return nil
            }
        })
    }

    private func retry(maxAttemptCount: Int, retryDelay: @escaping (Error) -> RetryDelay?) -> Observable<Element> {
        return self.retryWhen { errors in
            return errors.enumerated().flatMap { attempt, error -> Observable<Void> in
                guard (attempt + 1) < maxAttemptCount,
                      let delay = retryDelay(error) else {
                    return .error(error)
                }
                let seconds = Int(delay.seconds(for: (attempt + 1)))
                return Observable<Int>.timer(.seconds(seconds),
                                             scheduler: MainScheduler.instance)
                                      .map { _ in () }
            }
        }
    }

    func log(request: ApiRequest, url: URL?) -> Observable<Element> {
        return self.do(onNext: { response in
                   ApiLogger.log(request: request, url: (url ?? response.0.url))
                   ApiLogger.log(response: response, error: nil, for: request)
               }, onError: { error in
                   ApiLogger.log(request: request, url: url)
                   ApiLogger.log(response: nil, error: error, for: request)
               })
    }
}

extension ObservableType where Element == DataRequest {
    func responseDataWithResponseError(queue: DispatchQueue? = nil) -> Observable<(HTTPURLResponse, Data)> {
        return self.flatMap { $0.rx.responseDataWithResponseError(queue: queue) }
    }

    func validate() -> Observable<Element> {
        return self.map { $0.validate() }
    }
}

extension DataRequest {
    func validate() -> Self {
       return self.validate(contentType: self.acceptableContentTypes)
                  .validate { request, response, _ -> Request.ValidationResult in
                      if (response.statusCode >= 200 && response.statusCode < 300) || response.statusCode == 304 {
                          return .success
                      }
                      return .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)))
                  }
    }
}

extension DataRequest {
    var acceptableContentTypes: [String] {
        return self.request?.value(forHTTPHeaderField: "Accept")?.components(separatedBy: ",") ?? ["*/*"]
    }
}

extension DataResponse where Value == Data {
    func log(request: ApiRequest) -> Self {
        guard let response = self.response else { return self }

        ApiLogger.log(request: request, url: self.request?.url)
        switch self.result {
        case .success(let data):
            ApiLogger.log(response: (response, data), error: nil, for: request)
        case .failure(let error):
            ApiLogger.log(response: nil, error: error, for: request)
        }

        return self
    }
}

extension Reactive where Base: DataRequest {
    fileprivate func responseDataWithResponseError(queue: DispatchQueue? = nil) -> Observable<(HTTPURLResponse, Data)> {
        return self.responseResultWithResponseError(queue: queue, responseSerializer: DataRequest.dataResponseSerializer())
    }

    private func responseResultWithResponseError<T: DataResponseSerializerProtocol>(queue: DispatchQueue? = nil,
                                                                                    responseSerializer: T)
                                                                  -> Observable<(HTTPURLResponse, T.SerializedObject)> {
        return Observable.create { observer in
            let dataRequest = self.base.response(queue: queue, responseSerializer: responseSerializer) { response in
                    switch response.result {
                    case .success(let result):
                        if let httpResponse = response.response {
                            observer.on(.next((httpResponse, result)))
                            observer.on(.completed)
                        } else {
                            let error = AFResponseError(error: AFError.responseSerializationFailed(reason: .inputDataNil),
                                                        headers: response.response?.allHeaderFields,
                                                        response: "")
                            observer.on(.error(error))
                        }
                    case .failure(let error):
                        if let alamoError = error as? AFError {
                            let responseString = response.data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
                            let responseError = AFResponseError(error: alamoError,
                                                                headers: response.response?.allHeaderFields,
                                                                response: responseString)
                            observer.on(.error(responseError))
                        } else {
                            observer.on(.error(error))
                        }
                    }
            }

            return Disposables.create {
                dataRequest.cancel()
            }
        }
    }
}
