//
//  ItemCellModel.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

typealias ItemCellAttachmentData = (Attachment.ContentType, CGFloat?, Error?)

struct ItemCellModel {
    let key: String
    let typeIconName: String
    let title: String
    let subtitle: String
    let hasNote: Bool
    let tagColors: [UIColor]
    let attachment: ItemCellAttachmentData?

    init(item: RItem, attachment: ItemCellAttachmentData?) {
        self.key = item.key
        self.typeIconName = ItemCellModel.iconName(for: item)
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
        return item.tags.compactMap({ $0.color.isEmpty ? nil : $0.color }).map({ UIColor(hex: $0) })
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

    private static func iconName(for item: RItem) -> String {
        switch item.rawType {
        case "artwork":
            return Asset.Images.ItemTypes.artwork.name
        case "attachment":
            let contentType = item.fields.filter(.key(FieldKeys.contentType)).first?.value ?? ""
            if contentType.contains("pdf") {
                return Asset.Images.ItemTypes.pdf.name
            }
            return Asset.Images.ItemTypes.document.name
        case "audioRecording":
            return Asset.Images.ItemTypes.audioRecording.name
        case "book":
            return Asset.Images.ItemTypes.book.name
        case "bookSection":
            return Asset.Images.ItemTypes.bookSection.name
        case "bill":
            return Asset.Images.ItemTypes.bill.name
        case "blogPost":
            return Asset.Images.ItemTypes.blogPost.name
        case "case":
            return Asset.Images.ItemTypes.case.name
        case "computerProgram":
            return Asset.Images.ItemTypes.computerProgram.name
        case "conferencePaper":
            return Asset.Images.ItemTypes.conferencePaper.name
        case "dictionaryEntry":
            return Asset.Images.ItemTypes.dictionaryEntry.name
        case "document":
            return Asset.Images.ItemTypes.document.name
        case "email":
            return Asset.Images.ItemTypes.email.name
        case "encyclopediaArticle":
            return Asset.Images.ItemTypes.encyclopediaArticle.name
        case "film":
            return Asset.Images.ItemTypes.film.name
        case "forumPost":
            return Asset.Images.ItemTypes.forumPost.name
        case "hearing":
            return Asset.Images.ItemTypes.hearing.name
        case "instantMessage":
            return Asset.Images.ItemTypes.instantMessage.name
        case "interview":
            return Asset.Images.ItemTypes.interview.name
        case "journalArticle":
            return Asset.Images.ItemTypes.journalArticle.name
        case "letter":
            return Asset.Images.ItemTypes.letter.name
        case "magazineArticle":
            return Asset.Images.ItemTypes.magazineArticle.name
        case "map":
            return Asset.Images.ItemTypes.map.name
        case "manuscript":
            return Asset.Images.ItemTypes.manuscript.name
        case "note":
            return Asset.Images.ItemTypes.note.name
        case "newspaperArticle":
            return Asset.Images.ItemTypes.newspaperArticle.name
        case "patent":
            return Asset.Images.ItemTypes.patent.name
        case "podcast":
            return Asset.Images.ItemTypes.podcast.name
        case "presentation":
            return Asset.Images.ItemTypes.presentation.name
        case "radioBroadcast":
            return Asset.Images.ItemTypes.radioBroadcast.name
        case "report":
            return Asset.Images.ItemTypes.report.name
        case "statute":
            return Asset.Images.ItemTypes.statute.name
        case "thesis":
            return Asset.Images.ItemTypes.thesis.name
        case "tvBroadcast":
            return Asset.Images.ItemTypes.tvBroadcast.name
        case "videoRecording":
            return Asset.Images.ItemTypes.videoRecording.name
        case "webpage":
            return Asset.Images.ItemTypes.webPage.name
        default:
            return "unknown"
        }
    }
}
