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
}

extension ObservableType where Element == DataRequest {
    func responseDataWithResponseError(queue: DispatchQueue, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(HTTPURLResponse, Data?)> {
        return self.flatMap { $0.rx.responseDataWithResponseError(queue: queue, encoding: encoding, logParams: logParams) }
    }

    func responseDataWithResponseError(queue: DispatchQueue, acceptableStatusCodes: Set<Int>, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(HTTPURLResponse, Data)> {
        return self.flatMap { $0.rx.responseDataWithResponseError(queue: queue, acceptableStatusCodes: acceptableStatusCodes, encoding: encoding, logParams: logParams) }
    }

    func validate(acceptableStatusCodes: Set<Int>) -> Observable<Element> {
        return self.map { $0.validate(acceptableStatusCodes: acceptableStatusCodes) }
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
}

extension Reactive where Base: DataRequest {
    func responseDataWithResponseError(queue: DispatchQueue, acceptableStatusCodes: Set<Int>, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(HTTPURLResponse, Data)> {
        return self.responseResultWithResponseError(queue: queue, responseSerializer: DataResponseSerializer(emptyResponseCodes: acceptableStatusCodes), encoding: encoding, logParams: logParams)
    }

    func responseDataWithResponseError(queue: DispatchQueue, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(HTTPURLResponse, Data?)> {
        return Observable.create { observer in
            var logData: ApiLogger.StartData?

            let dataRequest = self.base.response(queue: queue) { response in
                switch response.logAndCreateResult(logData: logData) {
                case .success((let response, let data)):
                    observer.on(.next((response, data)))
                    observer.on(.completed)

                case .failure(let error):
                    observer.on(.error(error))
                }
            }

            dataRequest.onURLRequestCreation(on: queue) { request in
                logData = ApiLogger.log(urlRequest: request, encoding: encoding, logParams: logParams)
            }

            return Disposables.create {
                dataRequest.cancel()
            }
        }
    }

    private func responseResultWithResponseError<T: DataResponseSerializerProtocol>(queue: DispatchQueue, responseSerializer: T,
                                                                                    encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(HTTPURLResponse, T.SerializedObject)> {
        return Observable.create { observer in
            var logData: ApiLogger.StartData?

            let dataRequest = self.base.response(queue: queue, responseSerializer: responseSerializer) { response in
                switch response.result {
                case .success(let result):
                    if let httpResponse = response.response {
                        if let data = logData {
                            ApiLogger.logSuccessfulResponse(statusCode: (response.response?.statusCode ?? -1), data: response.data, headers: response.response?.allHeaderFields ?? [:], startData: data)
                        }

                        observer.on(.next((httpResponse, result)))
                        observer.on(.completed)
                    } else {
                        let responseString = ResponseCreator.string(from: response.data, mimeType: (response.response?.mimeType ?? "")) ?? ""
                        let error = AFResponseError(error: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength), headers: response.response?.allHeaderFields, response: responseString)

                        if let data = logData {
                            ApiLogger.logFailedresponse(error: error, statusCode: (response.response?.statusCode ?? -1), startData: data)
                        }

                        observer.on(.error(error))
                    }
                case .failure(let error):
                    let responseString = ResponseCreator.string(from: response.data, mimeType: (response.response?.mimeType ?? "")) ?? ""
                    let responseError = AFResponseError(error: error, headers: response.response?.allHeaderFields, response: responseString)

                    if let data = logData {
                        ApiLogger.logFailedresponse(error: responseError, statusCode: (response.response?.statusCode ?? -1), startData: data)
                    }

                    observer.on(.error(responseError))
                }
            }

            dataRequest.onURLRequestCreation(on: queue) { request in
                logData = ApiLogger.log(urlRequest: request, encoding: encoding, logParams: logParams)
            }

            return Disposables.create {
                dataRequest.cancel()
            }
        }
    }


}

extension AFDataResponse where Success == Data?, Failure == AFError {
    func logAndCreateResult(logData: ApiLogger.StartData?) -> Result<(HTTPURLResponse, Data?), AFResponseError> {
        switch self.result {
        case .success(let data):
            if let httpResponse = self.response {
                if let logData = logData {
                    ApiLogger.logSuccessfulResponse(statusCode: (self.response?.statusCode ?? -1), data: data, headers: (self.response?.allHeaderFields ?? [:]), startData: logData)
                }
                return .success((httpResponse, data))
            }

            let responseString = ResponseCreator.string(from: data, mimeType: (self.response?.mimeType ?? "")) ?? ""
            let error = AFResponseError(error: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength), headers: self.response?.allHeaderFields, response: responseString)

            if let data = logData {
                ApiLogger.logFailedresponse(error: error, statusCode: (self.response?.statusCode ?? -1), startData: data)
            }

            return .failure(error)

        case .failure(let error):
            let responseString = ResponseCreator.string(from: self.data, mimeType: (self.response?.mimeType ?? "")) ?? ""
            let responseError = AFResponseError(error: error, headers: self.response?.allHeaderFields, response: responseString)

            if let data = logData {
                ApiLogger.logFailedresponse(error: responseError, statusCode: (self.response?.statusCode ?? -1), startData: data)
            }

            return .failure(responseError)
        }
    }
}

fileprivate struct ResponseCreator {
    static func string(from data: Data?, mimeType: String) -> String? {
        guard mimeType == "text/plain" else { return nil }
        return data.flatMap({ String(data: $0, encoding: .utf8) })
    }
}
