//
//  ItemDetailAction.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemDetailAction {
    enum CreatorUpdate {
        case namePresentation(ItemDetailState.Creator.NamePresentation)
        case firstName(String)
        case lastName(String)
        case fullName(String)
        case type(String)
    }

    case acceptPrompt
    case addAttachments([URL])
    case addCreator
    case cancelEditing
    case cancelPrompt
    case changeType(String)
    case deleteAttachments(IndexSet)
    case deleteCreators(IndexSet)
    case deleteNotes(IndexSet)
    case deleteTags(IndexSet)
    case moveCreators(from: IndexSet, to: Int)
    case openAttachment(Attachment)
    case saveNote(key: String?, text: String)
    case setFieldValue(id: String, value: String)
    case setTags([Tag])
    case setTitle(String)
    case save
    case startEditing
    case updateCreator(UUID, CreatorUpdate)
}
