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
    let iconRenderingMode: UIImage.RenderingMode
    let typeName: String
    let title: NSAttributedString
    let subtitle: String
    let hasNote: Bool
    let tagColors: [UIColor]
    let tagEmojis: [String]
    let accessory: Accessory?
    let hasDetailButton: Bool

    init(item: RItem, typeName: String, title: NSAttributedString, accessory: Accessory?) {
        key = item.key
        typeIconName = Self.typeIconName(for: item)
        iconRenderingMode = .alwaysOriginal
        self.typeName = typeName
        self.title = title
        subtitle = Self.creatorSummary(for: item)
        hasNote = Self.hasNote(item: item)
        self.accessory = accessory
        let (colors, emojis) = Self.tagData(item: item)
        tagColors = colors
        tagEmojis = emojis
        hasDetailButton = true
    }

    init(item: RItem, typeName: String, title: NSAttributedString, accessory: ItemAccessory?, fileDownloader: AttachmentDownloader?) {
        self.init(item: item, typeName: typeName, title: title, accessory: Self.createAccessory(from: accessory, fileDownloader: fileDownloader))
    }

    init(collectionWithKey key: String, title: NSAttributedString) {
        self.key = key
        self.title = title
        accessory = nil
        typeIconName = Asset.Images.Cells.collection.name
        iconRenderingMode = .alwaysTemplate
        subtitle = ""
        hasNote = false
        tagColors = []
        tagEmojis = []
        typeName = L10n.Accessibility.Items.collection
        hasDetailButton = false
    }

    static func createAccessory(from accessory: ItemAccessory?, fileDownloader: AttachmentDownloader?) -> ItemCellModel.Accessory? {
        return accessory.flatMap({ accessory -> ItemCellModel.Accessory in
            switch accessory {
            case .attachment(let attachment, let parentKey):
                let (progress, error) = fileDownloader?.data(for: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId) ?? (nil, nil)
                return .attachment(.stateFrom(type: attachment.type, progress: progress, error: error))

            case .doi:
                return .doi

            case .url:
                return .url
            }
        })
    }

    static func hasNote(item: RItem) -> Bool {
        return !item.children
            .filter(.items(type: ItemTypes.note, notSyncState: .dirty))
            .filter(.isTrash(false))
            .isEmpty
    }

    static func typeIconName(for item: RItem) -> String {
        var data: ItemTypes.AttachmentData?
        if item.rawType == ItemTypes.attachment,
           let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value,
           let linkMode = item.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first.flatMap({ LinkMode(rawValue: $0.value) }) {
            data = .init(contentType: contentType, linked: linkMode == .linkedFile)
        }
        return ItemTypes.iconName(for: item.rawType, attachmentData: data)
    }

    static func tagData(item: RItem) -> ([UIColor], [String]) {
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

    static func creatorSummary(for item: RItem) -> String {
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
