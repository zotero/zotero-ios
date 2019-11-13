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
                .padding(.vertical, 8)
                .padding(.horizontal, 15)
                .frame(width: 45)

            VStack(alignment: .leading, spacing: 6) {
                Text(self.item.displayTitle.isEmpty ? " " : self.item.displayTitle)
                    .font(.headline)
                    .fontWeight(.regular)

                HStack {
                    Text(self.item.subtitle ?? " ")
                        .foregroundColor(.gray)
                    Spacer()
                    if self.item.hasAttachment {
                        Image("indicator_attachment")
                    }
                    if self.item.hasNote {
                        Image("indicator_note")
                    }
                    TagCirclesView(colors: self.item.tagHexColors, height: 16)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

extension RItem {
    fileprivate var iconName: String {
        switch self.rawType {
        case "artwork":
            return "artwork"
        case "attachment":
            let contentType = self.fields.filter(.key(FieldKeys.contentType)).first?.value ?? ""
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

    fileprivate var subtitle: String? {
        guard self.creatorSummary != nil || self.parsedYear != nil else { return nil }
        var result = self.creatorSummary ?? ""
        if !result.isEmpty {
            result += " "
        }
        if let year = self.parsedYear {
            result += "(\(year))"
        }
        return result
    }

    fileprivate var hasAttachment: Bool {
        return self.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty))
                            .filter(.isTrash(false))
                            .count > 0
    }

    fileprivate var hasNote: Bool {
        return self.children.filter(.items(type: ItemTypes.note, notSyncState: .dirty))
                            .filter(.isTrash(false))
                            .count > 0
    }

    fileprivate var tagHexColors: [String] {
        return self.tags.compactMap({ $0.color.isEmpty ? nil : $0.color })
    }
}

struct ItemRow_Previews: PreviewProvider {
    static var previews: some View {
        let item = RItem()
        item.displayTitle = "Bitcoin: A Peer-to-Peer Electronics Cash System"
        item.rawType = "artwork"
        item.creatorSummary = "Author"
        let item2 = RItem()
        item2.displayTitle = "Some audio recording"
        item2.rawType = "audioRecording"
        item2.creatorSummary = "Author"
        item2.parsedYear = "2018"
        let item3 = RItem()
        item3.displayTitle = "Some thesis"
        item3.rawType = "thesis"
        item3.creatorSummary = "Author"
        item3.parsedYear = "2019"

        return List {
            ItemRow(item: item)
            ItemRow(item: item2)
            ItemRow(item: item3)
        }
    }
}
