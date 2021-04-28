//
//  ItemAccessory.swift
//  Zotero
//
//  Created by Michal Rentka on 28.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemAccessory {
    case attachment(Attachment)
    case doi(String)
    case url(URL)
}

extension ItemAccessory {
    func updatedAttachment(update: (Attachment) -> Attachment?) -> ItemAccessory? {
        switch self {
        case .attachment(let attachment):
            if let new = update(attachment) {
                return .attachment(new)
            }
            return nil
        case .doi, .url:
            return nil
        }
    }

    var attachment: Attachment? {
        switch self {
        case .attachment(let attachment): return attachment
        case .doi, .url: return nil
        }
    }
}
