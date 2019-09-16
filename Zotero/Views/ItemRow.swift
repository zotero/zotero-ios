//
//  ItemRow.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemRow: View {
    let item: RItem

    var body: some View {
        HStack {
            Image(self.item.iconName)
                .renderingMode(.template)
                .foregroundColor(.blue)
                .padding(.vertical, 8)
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 6) {
                Text(self.item.title)
                    .font(.headline)
                    .fontWeight(.regular)
                HStack {
                    self.item.subtitle.flatMap {
                        Text($0)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if self.item.hasAttachment {
                        Image(systemName: "paperclip")
                    }
                    if self.item.hasNote {
                        Image(systemName: "doc.text")
                    }
                    TagCirclesView(colors: self.item.tagHexColors)
                }
            }
        }
    }
}

struct ItemCell_Previews: PreviewProvider {
    static var previews: some View {
        let item = RItem()
        item.title = "Bitcoin: A Peer-to-Peer Electronics Cash System"
        item.rawType = "artwork"
        item.creatorSummary = "Rentka"
        item.parsedDate = "2014"
        return List { ItemRow(item: item) }
    }
}

extension RItem {
    fileprivate var iconName: String {
        switch self.rawType {
        case "artwork":
            return "icon_item_type_artwork"
        case "attachment":
            return "icon_item_type_attachment"
        case "audioRecording":
            return "icon_item_type_audio-recording"
        case "book":
            return "icon_item_type_book"
        case "bookSection":
            return "icon_item_type_book-section"
        case "bill":
            return "icon_item_type_bill"
        case "blogPost":
            return "icon_item_type_blog-post"
        case "case":
            return "icon_item_type_case"
        case "computerProgram":
            return "icon_item_type_computer-program"
        case "conferencePaper":
            return "icon_item_type_conference-paper"
        case "dictionaryEntry":
            return "icon_item_type_dictionary-entry"
        case "document":
            return "icon_item_type_document"
        case "email":
            return "icon_item_type_e-mail"
        case "encyclopediaArticle":
            return "icon_item_type_encyclopedia-article"
        case "film":
            return "icon_item_type_film"
        case "forumPost":
            return "icon_item_type_forum-post"
        case "hearing":
            return "icon_item_type_hearing"
        case "instantMessage":
            return "icon_item_type_instant-message"
        case "interview":
            return "icon_item_type_interview"
        case "journalArticle":
            return "icon_item_type_journal-article"
        case "letter":
            return "icon_item_type_letter"
        case "magazineArticle":
            return "icon_item_type_magazine-article"
        case "map":
            return "icon_item_type_map"
        case "manuscript":
            return "icon_item_type_manuscript"
        case "note":
            return "icon_item_type_note"
        case "newspaperArticle":
            return "icon_item_type_newspaper-article"
        case "patent":
            return "icon_item_type_patent"
        case "podcast":
            return "icon_item_type_podcast"
        case "presentation":
            return "icon_item_type_presentation"
        case "radioBroadcast":
            return "icon_item_type_radio-broadcast"
        case "report":
            return "icon_item_type_report"
        case "statute":
            return "icon_item_type_statute"
        case "thesis":
            return "icon_item_type_thesis"
        case "tvBroadcast":
            return "icon_item_type_tv-broadcast"
        case "videoRecording":
            return "icon_item_type_video-recording"
        case "webpage":
            return "icon_item_type_web-page"
        default:
            return "icon_item_type_unknown"
        }
    }

    fileprivate var subtitle: String? {
        if self.creatorSummary.isEmpty && self.parsedDate.isEmpty { return nil }

        var subtitle = "(\(self.creatorSummary)"
        if !self.parsedDate.isEmpty {
            if subtitle.count > 1 {
                subtitle += ", "
            }
        }
        return subtitle + "\(self.parsedDate))"
    }

    fileprivate var hasAttachment: Bool {
        return true//self.children.filter(Predicates.items(type: ItemTypes.attachment, notSyncState: .dirty)).count > 0
    }

    fileprivate var hasNote: Bool {
        return true//self.children.filter(Predicates.items(type: ItemTypes.note, notSyncState: .dirty)).count > 0
    }

    fileprivate var tagHexColors: [String] {
        return self.tags.compactMap({ $0.color.isEmpty ? nil : $0.color })
    }
}
