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
    let attachment: (AttachmentView.AttachmentType, AttachmentView.State)?

    init(item: RItem, contentType: Attachment.ContentType?) {
        self.key = item.key
        self.typeIconName = ItemCellModel.iconName(for: item)
        self.title = item.displayTitle
        self.subtitle = ItemCellModel.subtitle(for: item)
        self.hasNote = ItemCellModel.hasNote(item: item)
        self.tagColors = ItemCellModel.tagColors(item: item)

        if let contentType = contentType {
            switch contentType {
            case .file(let file, _, let location):
                self.attachment = ItemCellModel.attachment(from: file, location: location)
            case .url:
                self.attachment = nil
            }
        } else {
            self.attachment = nil
        }
    }

    private static func attachment(from file: File, location: Attachment.FileLocation?) -> (AttachmentView.AttachmentType, AttachmentView.State) {
        let type: AttachmentView.AttachmentType
        switch file.ext {
        case "pdf":
            type = .pdf
        default:
            type = .document
        }

        let state: AttachmentView.State
        if let location = location {
            switch location {
            case .local:
                state = .downloaded
            case .remote:
                state = .downloadable
            }
        } else {
            state = .missing
        }

        return (type, state)
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
            return "artwork"
        case "attachment":
            let contentType = item.fields.filter(.key(FieldKeys.contentType)).first?.value ?? ""
            if contentType.contains("pdf") {
                return "pdf"
            }
            return "document"
        case "audioRecording":
            return "audio-recording"
        case "book":
            return "book"
        case "bookSection":
            return "book-section"
        case "bill":
            return "bill"
        case "blogPost":
            return "blog-post"
        case "case":
            return "case"
        case "computerProgram":
            return "computer-program"
        case "conferencePaper":
            return "conference-paper"
        case "dictionaryEntry":
            return "dictionary-entry"
        case "document":
            return "document"
        case "email":
            return "email"
        case "encyclopediaArticle":
            return "encyclopedia-article"
        case "film":
            return "film"
        case "forumPost":
            return "forum-post"
        case "hearing":
            return "hearing"
        case "instantMessage":
            return "instant-message"
        case "interview":
            return "interview"
        case "journalArticle":
            return "journal-article"
        case "letter":
            return "letter"
        case "magazineArticle":
            return "magazine-article"
        case "map":
            return "map"
        case "manuscript":
            return "manuscript"
        case "note":
            return "note"
        case "newspaperArticle":
            return "newspaper-article"
        case "patent":
            return "patent"
        case "podcast":
            return "podcast"
        case "presentation":
            return "presentation"
        case "radioBroadcast":
            return "radio-broadcast"
        case "report":
            return "report"
        case "statute":
            return "statute"
        case "thesis":
            return "thesis"
        case "tvBroadcast":
            return "tv-broadcast"
        case "videoRecording":
            return "video-recording"
        case "webpage":
            return "web-page"
        default:
            return "unknown"
        }
    }
}
