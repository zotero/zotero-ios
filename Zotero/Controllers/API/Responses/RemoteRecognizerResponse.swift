//
//  RemoteRecognizerResponse.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RemoteRecognizerResponse: Decodable {
    struct Author: Decodable {
        let firstName, lastName: String?
    }
    let arxiv, doi, isbn, abstract, language, title, type, year, pages, volume, url, issue, issn, container, publisher: String?
    let authors: [Author]
}
