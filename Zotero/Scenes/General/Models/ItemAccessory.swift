//
//  ItemAccessory.swift
//  Zotero
//
//  Created by Michal Rentka on 28.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemAccessory {
    case attachment(attachment: Attachment, parentKey: String?)
    case doi(String)
    case url(URL)
}

extension ItemAccessory {
    func updatedAttachment(update: (Attachment) -> Attachment?) -> ItemAccessory? {
        switch self {
        case .attachment(let attachment, let parentKey):
            if let new = update(attachment) {
                return .attachment(attachment: new, parentKey: parentKey)
            }
            return nil

        case .doi, .url:
            return nil
        }
    }

    var attachment: Attachment? {
        switch self {
        case .attachment(let attachment, _):
            return attachment

        case .doi, .url:
            return nil
        }
    }

    static func create(from item: RItem, fileStorage: FileStorage, urlDetector: UrlDetector) -> ItemAccessory? {
        if let attachment = AttachmentCreator.mainAttachment(for: item, fileStorage: fileStorage) {
            return .attachment(attachment: attachment, parentKey: (item.key != attachment.key) ? item.key : nil)
        }

        if let urlString = item.urlString, urlDetector.isUrl(string: urlString), let url = URL(string: urlString) {
            return .url(url)
        }

        if let doi = item.doi {
            return .doi(doi)
        }

        return nil
    }
}
