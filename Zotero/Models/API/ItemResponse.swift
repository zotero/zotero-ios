//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ItemResponse {
    struct Data {
        enum DataType: String {
            case artwork
            case attachment
            case audioRecording
            case book
            case bookSection
            case bill
            case blogPost
            case `case`
            case computerProgram
            case conferencePaper
            case dictionaryEntry
            case document
            case email
            case encyclopediaArticle
            case film
            case forumPost
            case hearing
            case instantMessage
            case interview
            case journalArticle
            case letter
            case magazineArticle
            case map
            case manuscript
            case note
            case newspaperArticle
            case patent
            case podcast
            case presentation
            case radioBroadcast
            case report
            case statute
            case thesis
            case tvBroadcast
            case videoRecording
            case webpage
        }

        let type: DataType
        let title: String?
        let caseName: String?
        let subject: String?
        let nameOfAct: String?
        let note: String?
        let parentItem: String?
        let collections: [String]?
        let isTrash: Bool
    }

    let identifier: String
    let library: LibraryResponse
    let links: LinksResponse
    let data: ItemResponse.Data
    let version: Int
}

extension ItemResponse: Decodable {
    private enum Keys: String, CodingKey {
        case identifier = "key"
        case version, library, links, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ItemResponse.Keys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let library = try container.decode(LibraryResponse.self, forKey: .library)
        let links = try container.decode(LinksResponse.self, forKey: .links)
        let data = try container.decode(ItemResponse.Data.self, forKey: .data)
        let version = try container.decode(Int.self, forKey: .version)
        self.init(identifier: identifier, library: library, links: links, data: data, version: version)
    }
}

extension ItemResponse.Data: Decodable {
    private enum Keys: String, CodingKey {
        case itemType, parentItem, collections, deleted, title,
             caseName, subject, nameOfAct, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ItemResponse.Data.Keys.self)
        let rawType = try container.decode(String.self, forKey: .itemType)

        guard let type = ItemResponse.Data.DataType(rawValue: rawType) else {
            throw ZoteroApiError.unknownItemType(rawType)
        }

        let parentItem = try container.decodeIfPresent(String.self, forKey: .parentItem)
        let collections = try container.decodeIfPresent([String].self, forKey: .collections)
        let deleted = try container.decodeIfPresent(Int.self, forKey: .deleted)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let caseName = try container.decodeIfPresent(String.self, forKey: .caseName)
        let subject = try container.decodeIfPresent(String.self, forKey: .subject)
        let nameOfAct = try container.decodeIfPresent(String.self, forKey: .nameOfAct)
        let note = try container.decodeIfPresent(String.self, forKey: .note)

        self.init(type: type, title: title, caseName: caseName, subject: subject, nameOfAct: nameOfAct, note: note,
                  parentItem: parentItem, collections: collections, isTrash: (deleted == 1))
    }
}
