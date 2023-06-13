//
//  ItemTypes.swift
//  Zotero
//
//  Created by Michal Rentka on 07/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ItemTypes {
    static let note = "note"
    static let attachment = "attachment"
    static let `case` = "case"
    static let letter = "letter"
    static let interview = "interview"
    static let webpage = "webpage"
    static let annotation = "annotation"
    static let document = "document"

    static var excludedFromTypePicker: Set<String> = [ItemTypes.attachment, ItemTypes.annotation]
}

extension ItemTypes {
    static func iconName(for rawType: String, contentType: String?) -> String {
        switch rawType {
        case "artwork":
            return Asset.Images.ItemTypes.artwork.name
        case "attachment":
            if contentType?.contains("pdf") == true {
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
            return Asset.Images.ItemTypes.document.name
        }
    }
}
