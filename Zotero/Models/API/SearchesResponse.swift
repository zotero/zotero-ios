//
//  SearchesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SearchesResponse {
    let searches: [SearchResponse]
    let errors: [Error]
}

extension SearchesResponse: Decodable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var searches: [SearchResponse] = []
        var errors: [Error] = []

        while !container.isAtEnd {
            do {
                let search = try container.decode(SearchResponse.self)
                searches.append(search)
            } catch let error {
                errors.append(error)
            }
        }

        self.init(searches: searches, errors: errors)
    }
}

struct SearchResponse: Codable, KeyedResponse {
    struct Data: Codable {
        let name: String
        let conditions: [ConditionResponse]
    }

    let key: String
    let library: LibraryResponse
    let links: LinksResponse?
    let data: SearchResponse.Data
    let version: Int
}

struct ConditionResponse: Codable {
    let condition: String
    let `operator`: String
    let value: String
}
