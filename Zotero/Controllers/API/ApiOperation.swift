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
    private var request: DataRequest

    init(request: DataRequest, apiRequest: ApiRequest, queue: DispatchQueue, completion: @escaping (Swift.Result<(Data, ResponseHeaders), Error>) -> Void) {
        self.request = request

        super.init()

        self.request = self.request.log(request: apiRequest).responseData(queue: queue) { [weak self] response in
            guard let `self` = self else { return }
            switch response.log(request: apiRequest).result {
            case .success(let data):
                completion(.success((data, response.response?.allHeaderFields ?? [:])))
            case .failure(let error):
                completion(.failure(error))
            }
            self.finish()
        }
    }

    override func main() {
        super.main()
        self.request.resume()
    }

    override func cancel() {
        super.cancel()
        self.request.cancel()
    }
}
