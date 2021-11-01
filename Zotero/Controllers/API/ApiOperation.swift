//
//  ApiOperation.swift
//  Zotero
//
//  Created by Michal Rentka on 08/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

class ApiOperation: AsynchronousOperation {
    private let apiRequest: ApiRequest
    private let queue: DispatchQueue
    private let completion: (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void
    private unowned let requestCreator: ApiRequestCreator

    private var request: DataRequest?

    init(apiRequest: ApiRequest, requestCreator: ApiRequestCreator, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data?, HTTPURLResponse), Error>) -> Void) {
        self.apiRequest = apiRequest
        self.queue = queue
        self.completion = completion
        self.requestCreator = requestCreator

        super.init()
    }

    override func main() {
        super.main()

        if let request = self.request {
            request.resume()
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let request = self.requestCreator.dataRequest(for: self.apiRequest).log(request: apiRequest).response(queue: self.queue) { [weak self] response in
            guard let `self` = self, let httpResponse = response.response else { return }
            switch response.log(startTime: startTime, request: self.apiRequest).result {
            case .success(let data):
                self.completion(.success((data, httpResponse)))
            case .failure(let error):
                self.completion(.failure(error))
            }
            self.finish()
        }
        request.resume()
        self.request = request

    }

    override func cancel() {
        super.cancel()
        self.request?.cancel()
    }
}
