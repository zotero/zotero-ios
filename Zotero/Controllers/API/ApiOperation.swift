//
//  ApiOperation.swift
//  Zotero
//
//  Created by Michal Rentka on 08/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

class ApiOperation: AsynchronousOperation {
    private let apiRequest: ApiRequest
    private let responseQueue: DispatchQueue
    private let completion: (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void
    private unowned let apiClient: ApiClient

    private var disposeBag: DisposeBag?

    init(apiRequest: ApiRequest, apiClient: ApiClient, responseQueue: DispatchQueue, completion: @escaping (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void) {
        self.apiRequest = apiRequest
        self.apiClient = apiClient
        self.responseQueue = responseQueue
        self.completion = completion

        super.init()
    }

    override func main() {
        super.main()

        if self.disposeBag != nil {
            self.disposeBag = nil
        }

        let disposeBag = DisposeBag()
        self.apiClient.send(request: apiRequest, queue: self.responseQueue)
            .subscribe(with: self, onSuccess: { `self`, data in
                self.completion(.success(data))
                self.finish()
            }, onFailure: { `self`, error in
                self.completion(.failure(error))
                self.finish()
            })
            .disposed(by: disposeBag)
        self.disposeBag = disposeBag
    }

    override func cancel() {
        super.cancel()
        self.disposeBag = nil
    }
}
