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
    enum Kind: Codable {
        case zotero(uploadKey: String)
        case webdav(mtime: Int)

        private enum CodingKeys: String, CodingKey {
            case zoteroUploadKey, webdavMtime
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let uploadKey = try? container.decode(String.self, forKey: .zoteroUploadKey) {
                self = .zotero(uploadKey: uploadKey)
            } else {
                let mtime = try container.decode(Int.self, forKey: .webdavMtime)
                self = .webdav(mtime: mtime)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .zotero(let uploadKey):
                try container.encode(uploadKey, forKey: .zoteroUploadKey)

            case .webdav(let mtime):
                try container.encode(mtime, forKey: .webdavMtime)
            }
        }
    }

    let type: Kind
    let key: String
    let libraryId: LibraryIdentifier
    let userId: Int
    let remoteUrl: URL
    let fileUrl: URL
    let md5: String
    let sessionId: String
    let date: Date
    let size: UInt64

    var completion: BackgroundUploadCompletion?

    private enum CodingKeys: String, CodingKey {
        case type, key, libraryId, userId, remoteUrl, fileUrl, md5, uploadKey, sessionId, date, size
    }

    init(type: Kind, key: String, libraryId: LibraryIdentifier, userId: Int, remoteUrl: URL, fileUrl: URL, md5: String, date: Date, size: UInt64 = 0, sessionId: String = "", completion: BackgroundUploadCompletion? = nil) {
        self.type = type
        self.key = key
        self.libraryId = libraryId
        self.userId = userId
        self.remoteUrl = remoteUrl
        self.fileUrl = fileUrl
        self.md5 = md5
        self.sessionId = sessionId
        self.date = date
        self.size = size
        self.completion = completion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.libraryId = try container.decode(LibraryIdentifier.self, forKey: .libraryId)
        self.userId = try container.decode(Int.self, forKey: .userId)
        self.remoteUrl = try container.decode(URL.self, forKey: .remoteUrl)
        self.fileUrl = try container.decode(URL.self, forKey: .fileUrl)
        self.md5 = try container.decode(String.self, forKey: .md5)
        // Backwards compatibility
        self.sessionId = (try? container.decode(String.self, forKey: .sessionId)) ?? ""
        self.size = (try? container.decode(UInt64.self, forKey: .size)) ?? 0
        self.date = (try? container.decode(Date.self, forKey: .date)) ?? Date(timeIntervalSince1970: 0)

        if let uploadKey = try? container.decode(String.self, forKey: .uploadKey) {
            // Backwards compatibility
            self.type = .zotero(uploadKey: uploadKey)
        } else {
            self.type = try container.decode(Kind.self, forKey: .type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.key, forKey: .key)
        try container.encode(self.libraryId, forKey: .libraryId)
        try container.encode(self.userId, forKey: .userId)
        try container.encode(self.remoteUrl, forKey: .remoteUrl)
        try container.encode(self.fileUrl, forKey: .fileUrl)
        try container.encode(self.md5, forKey: .md5)
        try container.encode(self.sessionId, forKey: .sessionId)
        try container.encode(self.date, forKey: .date)
        try container.encode(self.size, forKey: .size)
    }

    func copy(withFileUrl fileUrl: URL, size: UInt64, andSessionId sessionId: String) -> BackgroundUpload {
        return BackgroundUpload(type: self.type,
                                key: self.key,
                                libraryId: self.libraryId,
                                userId: self.userId,
                                remoteUrl: self.remoteUrl,
                                fileUrl: fileUrl,
                                md5: self.md5,
                                date: self.date,
                                size: size,
                                sessionId: sessionId,
                                completion: self.completion)
    }
}
