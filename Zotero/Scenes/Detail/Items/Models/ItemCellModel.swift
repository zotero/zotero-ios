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
    let title: NSAttributedString
    let subtitle: String
    let hasNote: Bool
    let tagColors: [UIColor]
    let tagEmojis: [String]
    let accessory: Accessory?

    init(item: RItem, typeName: String, title: NSAttributedString, accessory: Accessory?) {
        self.key = item.key
        let contentType: String? = item.rawType == ItemTypes.attachment ? item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value : nil
        self.typeIconName = ItemTypes.iconName(for: item.rawType, contentType: contentType)
        self.typeName = typeName
        self.title = title
        self.subtitle = ItemCellModel.subtitle(for: item)
        self.hasNote = ItemCellModel.hasNote(item: item)
        self.accessory = accessory
        let (colors, emojis) = ItemCellModel.tagData(item: item)
        self.tagColors = colors
        self.tagEmojis = emojis
    }

    fileprivate static func hasNote(item: RItem) -> Bool {
        return !item.children
            .filter(.items(type: ItemTypes.note, notSyncState: .dirty))
            .filter(.isTrash(false))
            .isEmpty
    }

    fileprivate static func tagData(item: RItem) -> ([UIColor], [String]) {
        var colors: [UIColor] = []
        var emojis: [String] = []
        for tag in item.tags {
            if let emoji = tag.tag?.emojiGroup, !emoji.isEmpty {
                emojis.append(emoji)
                continue
            }

            let (color, style) = TagColorGenerator.uiColor(for: (tag.tag?.color ?? ""))
            if style == .filled {
                colors.append(color)
            }
        }
        return (colors, emojis)
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
