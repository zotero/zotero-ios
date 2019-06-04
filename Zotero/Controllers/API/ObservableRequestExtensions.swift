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

extension ObservableType where E == (HTTPURLResponse, Data) {
    func retryIfNeeded() -> Observable<E> {
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

    private func retry(maxAttemptCount: Int, retryDelay: @escaping (Error) -> RetryDelay?) -> Observable<E> {
        return retryWhen { errors in
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

    func log(request: ApiRequest, convertible: URLRequestConvertible) -> Observable<E> {
        return self.asObservable()
                   .do(onNext: { response in
                       #if DEBUG
                       self.logRequest(request, url: convertible.urlRequest?.url)
                       self.logResponse(data: response.1, error: nil)
                       #endif
                   }, onError: { error in
                       #if DEBUG
                       self.logRequest(request, url: convertible.urlRequest?.url)
                       self.logResponse(data: nil, error: error)
                       #endif
                   })
    }

    private func logRequest(_ request: ApiRequest, url: URL?) {
        DDLogInfo("--- API request '\(type(of: request))' ---")
        DDLogInfo("(\(request.httpMethod.rawValue)) \(url?.absoluteString ?? "")")
        if request.httpMethod != .get, let params = request.parameters {
            DDLogInfo("\(params)")
        }
    }

    private func logResponse(data: Data?, error: Error?) {
        if let data = data {
            let string = String(data: data, encoding: .utf8)
            DDLogInfo("\(string ?? "")")
        } else if let error = error {
            DDLogInfo("\(error)")
        }
    }
}

extension ObservableType where E == DataRequest {
    func responseDataWithResponseError() -> Observable<(HTTPURLResponse, Data)> {
        return self.flatMap { $0.rx.responseDataWithResponseError() }
    }
}

extension Reactive where Base: DataRequest {
    fileprivate func responseDataWithResponseError() -> Observable<(HTTPURLResponse, Data)> {
        return self.responseResultWithResponseError(responseSerializer: DataRequest.dataResponseSerializer())
    }

    fileprivate func responseResultWithResponseError<T: DataResponseSerializerProtocol>(queue: DispatchQueue? = nil,
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
