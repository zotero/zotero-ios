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
    let key: String
    let typeIconName: String
    let title: String
    let subtitle: String
    let hasNote: Bool
    let tagColors: [UIColor]
    let attachment: FileAttachmentView.State?

    init(item: RItem, attachment: FileAttachmentView.State?) {
        self.key = item.key
        let contentType: String? = item.rawType == ItemTypes.attachment ? item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value : nil
        self.typeIconName = ItemTypes.iconName(for: item.rawType, contentType: contentType)
        self.title = item.displayTitle
        self.subtitle = ItemCellModel.subtitle(for: item)
        self.hasNote = ItemCellModel.hasNote(item: item)
        self.tagColors = ItemCellModel.tagColors(item: item)
        self.attachment = attachment
    }

    fileprivate static func hasAttachment(item: RItem) -> Bool {
        return item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty))
                            .filter(.isTrash(false))
                            .count > 0
    }

    fileprivate static func hasNote(item: RItem) -> Bool {
        return item.children.filter(.items(type: ItemTypes.note, notSyncState: .dirty))
                            .filter(.isTrash(false))
                            .count > 0
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
