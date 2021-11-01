//
//  ObservableRequestExtensions.swift
//  Zotero
//
//  Created by Michal Rentka on 10/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
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
        return self.retry(when: { errors in
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
        })
    }

    func log(identifier: String, startTime: CFAbsoluteTime, request: ApiRequest) -> Observable<Element> {
        return self.do(onNext: { response in
                   ApiLogger.logData(result: .success(response), time: CFAbsoluteTimeGetCurrent() - startTime, identifier: identifier, request: request)
               }, onError: { error in
                   ApiLogger.logData(result: .failure(error), time: CFAbsoluteTimeGetCurrent() - startTime, identifier: identifier, request: request)
               })
    }
}

extension ObservableType where Element == HTTPURLResponse {
    func log(identifier: String, startTime: CFAbsoluteTime, request: ApiRequest) -> Observable<Element> {
        return self.do(onNext: { response in
                   ApiLogger.log(result: .success(response), time: CFAbsoluteTimeGetCurrent() - startTime, identifier: identifier, request: request)
               }, onError: { error in
                   ApiLogger.log(result: .failure(error), time: CFAbsoluteTimeGetCurrent() - startTime, identifier: identifier, request: request)
               })
    }
}

extension ObservableType where Element == DataRequest {
    func responseDataWithResponseError(queue: DispatchQueue, acceptableStatusCodes: Set<Int>) -> Observable<(HTTPURLResponse, Data)> {
        return self.flatMap { $0.rx.responseDataWithResponseError(queue: queue, acceptableStatusCodes: acceptableStatusCodes) }
    }

    func validate(acceptableStatusCodes: Set<Int>) -> Observable<Element> {
        return self.map { $0.validate(acceptableStatusCodes: acceptableStatusCodes) }
    }

    func log(request: ApiRequest) -> Observable<(Element, String)> {
        return self.map { element in
            let id = ApiLogger.log(request: request, url: element.request?.url)
            return (element, id)
        }
    }
}

extension DataRequest {
    func validate(acceptableStatusCodes: Set<Int>) -> Self {
       return self.validate(contentType: self.acceptableContentTypes)
                  .validate { request, response, _ -> Request.ValidationResult in
                      if acceptableStatusCodes.contains(response.statusCode) {
                          return .success(())
                      }
                      return .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: response.statusCode)))
                  }
    }

    var acceptableContentTypes: [String] {
        return self.request?.value(forHTTPHeaderField: "Accept")?.components(separatedBy: ",") ?? ["*/*"]
    }

    func log(request: ApiRequest) -> Self {
        _ = ApiLogger.log(request: request, url: self.request?.url)
        return self
    }
}

extension Reactive where Base: DataRequest {
    func responseDataWithResponseError(queue: DispatchQueue, acceptableStatusCodes: Set<Int>) -> Observable<(HTTPURLResponse, Data)> {
        return self.responseResultWithResponseError(queue: queue, responseSerializer: DataResponseSerializer(emptyResponseCodes: acceptableStatusCodes))
    }

    private func responseResultWithResponseError<T: DataResponseSerializerProtocol>(queue: DispatchQueue, responseSerializer: T) -> Observable<(HTTPURLResponse, T.SerializedObject)> {
        return Observable.create { observer in
            let dataRequest = self.base.response(queue: queue, responseSerializer: responseSerializer) { response in
                    switch response.result {
                    case .success(let result):
                        if let httpResponse = response.response {
                            observer.on(.next((httpResponse, result)))
                            observer.on(.completed)
                        } else {
                            let responseString = response.data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
                            let error = AFResponseError(error: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength),
                                                        headers: response.response?.allHeaderFields,
                                                        response: responseString)
                            observer.on(.error(error))
                        }
                    case .failure(let error):
                        let responseString = response.data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
                        let responseError = AFResponseError(error: error,
                                                            headers: response.response?.allHeaderFields,
                                                            response: responseString)
                        observer.on(.error(responseError))
                    }
            }

            return Disposables.create {
                dataRequest.cancel()
            }
        }
    }
}

extension DataResponse where Success == Data {
    func log(startTime: CFAbsoluteTime, request: ApiRequest) -> Self {
        guard let httpRequest = self.request, let response = self.response else { return self }
        let identifier = ApiLogger.identifier(method: request.httpMethod.rawValue, url: (httpRequest.url?.absoluteString ?? request.debugUrl))
        let time = CFAbsoluteTimeGetCurrent() - startTime

        switch self.result {
        case .success(let data):
            ApiLogger.logData(result: .success((response, data)), time: time, identifier: identifier, request: request)
        case .failure(let error):
            ApiLogger.logData(result: .failure(error), time: time, identifier: identifier, request: request)
        }
        return self
    }
}

extension DataResponse where Success == Data? {
    func log(startTime: CFAbsoluteTime, request: ApiRequest) -> Self {
        guard let httpRequest = self.request, let response = self.response else { return self }
        let identifier = ApiLogger.identifier(method: request.httpMethod.rawValue, url: (httpRequest.url?.absoluteString ?? request.debugUrl))
        let time = CFAbsoluteTimeGetCurrent() - startTime

        switch self.result {
        case .success(let data):
            if let data = data {
                ApiLogger.logData(result: .success((response, data)), time: time, identifier: identifier, request: request)
            } else {
                ApiLogger.log(result: .success(response), time: time, identifier: identifier, request: request)
            }
        case .failure(let error):
            ApiLogger.logData(result: .failure(error), time: time, identifier: identifier, request: request)
        }
        return self
    }
}
