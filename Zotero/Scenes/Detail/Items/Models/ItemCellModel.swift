//
//  ItemCellModel.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct ItemCellModel {
    enum Accessory {
        case attachment(FileAttachmentView.State)
        case doi
        case url
    }

    let key: String
    let typeIconName: String
    let typeName: String
    let title: String
    let subtitle: String
    let hasNote: Bool
    let tagColors: [UIColor]
    let accessory: Accessory?

    init(item: RItem, typeName: String, accessory: Accessory?) {
        self.key = item.key
        let contentType: String? = item.rawType == ItemTypes.attachment ? item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value : nil
        self.typeIconName = ItemTypes.iconName(for: item.rawType, contentType: contentType)
        self.typeName = typeName
        self.title = item.displayTitle
        self.subtitle = ItemCellModel.subtitle(for: item)
        self.hasNote = ItemCellModel.hasNote(item: item)
        self.tagColors = ItemCellModel.tagColors(item: item)
        self.accessory = accessory
    }

    fileprivate static func hasNote(item: RItem) -> Bool {
        return !item.children.filter(.items(type: ItemTypes.note, notSyncState: .dirty))
                             .filter(.isTrash(false))
                             .isEmpty
    }

    fileprivate static func tagColors(item: RItem) -> [UIColor] {
        return item.tags.compactMap({
            let (color, style) = TagColorGenerator.uiColor(for: ($0.tag?.color ?? ""))
            return style == .filled ? color : nil
        })
    }

    private static func subtitle(for item: RItem) -> String {
        guard item.creatorSummary != nil || item.parsedYear != 0 else { return "" }
        var result = item.creatorSummary ?? ""
        if !result.isEmpty {
            result += " "
        }
        if item.parsedYear > 0 {
            result += "(\(item.parsedYear))"
        }
        return result
    }
}
