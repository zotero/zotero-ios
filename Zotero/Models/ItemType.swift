//
//  ItemType.swift
//  Zotero
//
//  Created by Michal Rentka on 17/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum ItemType: String {
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
    case unknown
}

extension ItemType {
    var icon: UIImage? {
        let name: String
        switch self {
        case .artwork:
            name = "icon_item_type_artwork"
        case .attachment:
            name = "icon_item_type_attachment"
        case .audioRecording:
            name = "icon_item_type_audio-recording"
        case .book:
            name = "icon_item_type_book"
        case .bookSection:
            name = "icon_item_type_book-section"
        case .bill:
            name = "icon_item_type_bill"
        case .blogPost:
            name = "icon_item_type_blog-post"
        case .case:
            name = "icon_item_type_case"
        case .computerProgram:
            name = "icon_item_type_computer-program"
        case .conferencePaper:
            name = "icon_item_type_conference-paper"
        case .dictionaryEntry:
            name = "icon_item_type_dictionary-entry"
        case .document:
            name = "icon_item_type_document"
        case .email:
            name = "icon_item_type_e-mail"
        case .encyclopediaArticle:
            name = "icon_item_type_encyclopedia-article"
        case .film:
            name = "icon_item_type_film"
        case .forumPost:
            name = "icon_item_type_forum-post"
        case .hearing:
            name = "icon_item_type_hearing"
        case .instantMessage:
            name = "icon_item_type_instant-message"
        case .interview:
            name = "icon_item_type_interview"
        case .journalArticle:
            name = "icon_item_type_journal-article"
        case .letter:
            name = "icon_item_type_letter"
        case .magazineArticle:
            name = "icon_item_type_magazine-article"
        case .map:
            name = "icon_item_type_map"
        case .manuscript:
            name = "icon_item_type_manuscript"
        case .note:
            name = "icon_item_type_note"
        case .newspaperArticle:
            name = "icon_item_type_newspaper-article"
        case .patent:
            name = "icon_item_type_patent"
        case .podcast:
            name = "icon_item_type_podcast"
        case .presentation:
            name = "icon_item_type_presentation"
        case .radioBroadcast:
            name = "icon_item_type_radio-broadcast"
        case .report:
            name = "icon_item_type_report"
        case .statute:
            name = "icon_item_type_statute"
        case .thesis:
            name = "icon_item_type_thesis"
        case .tvBroadcast:
            name = "icon_item_type_tv-broadcast"
        case .videoRecording:
            name = "icon_item_type_video-recording"
        case .webpage:
            name = "icon_item_type_web-page"
        case .unknown:
            name = "icon_item_type_unknown"
        }
        return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
    }
}
