//
//  ItemDetailAction.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemDetailAction {
    case acceptPrompt
    case addAttachments([URL])
    case cancelEditing
    case cancelPrompt
    case changeType(String)
    case deleteAttachmentFile(Attachment)
    case deleteAttachments(IndexSet)
    case deleteCreator(UUID)
    case deleteCreators(IndexSet)
    case deleteNotes(IndexSet)
    case deleteTags(IndexSet)
    case moveCreators(from: IndexSet, to: Int)
    case openAttachment(Int)
    case reloadData
    case saveNote(key: String?, text: String)
    case setFieldValue(id: String, value: String)
    case setTags([Tag])
    case setTitle(String)
    case setAbstract(String)
    case save
    case saveCreator(ItemDetailState.Creator)
    case startEditing
    case trashAttachment(Attachment)
    case toggleAbstractDetailCollapsed
    case updateDownload(FileDownloader.Update)
    case updateAttachments(AttachmentFileDeletedNotification)
}
