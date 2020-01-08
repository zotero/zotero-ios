//
//  BackgroundUpload.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

typealias BackgroundUploadCompletion = (Result<BackgroundUpload, Error>) -> Void

struct BackgroundUpload: Codable {
    let key: String
    let libraryId: LibraryIdentifier
    let userId: Int
    let remoteUrl: URL
    let fileUrl: URL
    let uploadKey: String

    var completion: BackgroundUploadCompletion?

    private enum CodingKeys: String, CodingKey {
        case key, libraryId, userId, remoteUrl, fileUrl, uploadKey
    }
}
