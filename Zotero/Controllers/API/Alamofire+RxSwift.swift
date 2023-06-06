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
import RxSwift

struct AFResponseError: Error {
    let url: URL?
    let error: AFError
    let headers: [AnyHashable: Any]?
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

extension PrimitiveSequence where Trait == SingleTrait, Element == (Data?, HTTPURLResponse) {
    func mapData(httpMethod: String) -> Single<(Data, HTTPURLResponse)> {
        self.flatMap { data, response in
            if let data = data {
                return Single.just((data, response))
            }

            let error = ZoteroApiError.responseMissing(ApiLogger.identifier(method: httpMethod, url: (response.url?.absoluteString ?? "")))
            return Single.error(error)
        }
    }
}

extension ObservableType where Element == (Data?, HTTPURLResponse) {
    func retryIfNeeded() -> Observable<Element> {
        return self.retry(maxAttemptCount: 10, retryDelay: { error -> RetryDelay? in
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

extension Request: ReactiveCompatible {}

extension Reactive where Base: DataRequest {
    func loggedResponseDataWithResponseError(queue: DispatchQueue, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<(Data?, HTTPURLResponse)> {
        return Observable.create { observer in
            var logData: ApiLogger.StartData?

            let dataRequest = self.base.response(queue: queue) { response in
                switch response.logAndCreateResult(logData: logData) {
                case .success((let data, let response)):
                    observer.on(.next((data, response)))
                    observer.on(.completed)

                case .failure(let error):
                    observer.on(.error(error))
                }
            }

            dataRequest.onURLRequestCreation(on: queue) { request in
                logData = ApiLogger.log(urlRequest: request, encoding: encoding, logParams: logParams)
            }

            dataRequest.resume()

            return Disposables.create {
                dataRequest.cancel()
            }
        }
    }
}

extension Reactive where Base: DownloadRequest {
    func loggedResponseWithResponseError(queue: DispatchQueue, encoding: ApiParameterEncoding, logParams: ApiLogParameters) -> Observable<Base> {
        return Observable.create { observer in
            var logData: ApiLogger.StartData?

            let downloadRequest = self.base.response(queue: queue) { response in
                switch response.logAndCreateResult(logData: logData) {
                case .success:
                    observer.on(.completed)

                case .failure(let error):
                    observer.on(.error(error))
                }
            }

            downloadRequest.onURLRequestCreation(on: queue) { request in
                logData = ApiLogger.log(urlRequest: request, encoding: encoding, logParams: logParams)
            }

            observer.on(.next(self.base))

            return Disposables.create {
                downloadRequest.cancel()
            }
        }
    }
}

extension Progress {
    var observable: Observable<Progress> {
        return Observable.create { subscriber in
            var observer: NSKeyValueObservation? = self.observe(\.fractionCompleted) { progress, _ in
                subscriber.on(.next(progress))
                if progress.isFinished || progress.isCancelled {
                    subscriber.on(.completed)
                }
            }
            return Disposables.create {
                if observer != nil {
                    observer = nil
                }
            }
        }
    }
}

extension AFDataResponse where Success == Data?, Failure == AFError {
    func logAndCreateResult(logData: ApiLogger.StartData?) -> Result<(Data?, HTTPURLResponse), AFResponseError> {
        switch self.result {
        case .success(let data):
            if let httpResponse = self.response {
                if let logData = logData {
                    ApiLogger.logSuccessfulResponse(statusCode: (self.response?.statusCode ?? -1), data: data, headers: (self.response?.allHeaderFields ?? [:]), startData: logData)
                }
                return .success((data, httpResponse))
            }
            // Should not happen
            let afError = AFError.responseValidationFailed(reason: .customValidationFailed(error: ZoteroApiError.responseMissing(logData?.id ?? "")))
            return .failure(self.createResponseError(with: afError, url: self.request?.url, data: data, response: nil, logData: logData))

        case .failure(let error):
            return .failure(self.createResponseError(with: error, url: self.request?.url, data: self.data, response: self.response, logData: logData))
        }
    }

    private func createResponseError(with error: AFError, url: URL?, data: Data?, response: HTTPURLResponse?, logData: ApiLogger.StartData?) -> AFResponseError {
        let responseString = data.flatMap({ ResponseCreator.string(from: $0, mimeType: (response?.mimeType ?? "")) }) ?? "No Response"
        let responseError = AFResponseError(url: url, error: error, headers: response?.allHeaderFields, response: responseString)

        if let data = logData {
            ApiLogger.logFailedresponse(error: responseError, statusCode: (self.response?.statusCode ?? -1), startData: data)
        }

        return responseError
    }
}

extension AFDownloadResponse where Success == URL?, Failure == AFError {
    func logAndCreateResult(logData: ApiLogger.StartData?) -> Result<(), AFResponseError> {
        switch self.result {
        case .success:
            if let logData = logData {
                ApiLogger.logSuccessfulResponse(statusCode: (self.response?.statusCode ?? -1), data: nil, headers: (self.response?.allHeaderFields ?? [:]), startData: logData)
            }
            return .success(())

        case .failure(let error):
            let responseError = AFResponseError(url: self.request?.url, error: error, headers: self.response?.allHeaderFields, response: "Download failed")
            if let data = logData {
                ApiLogger.logFailedresponse(error: responseError, statusCode: (self.response?.statusCode ?? -1), startData: data)
            }
            return .failure(responseError)
        }
    }
}

fileprivate struct ResponseCreator {
    static func string(from data: Data?, mimeType: String) -> String? {
        switch mimeType {
        case "text/plain", "text/html", "application/xml", "application/json":
            return data.flatMap({ String(data: $0, encoding: .utf8) })
        default:
            return nil
        }
    }
}
