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
    case deleteAttachment(Attachment)
    case deleteCreator(String)
    case deleteNote(key: String)
    case deleteTag(Tag)
    case endEditing
    case loadInitialData
    case moveCreators(CollectionDifference<String>)
    case moveAttachmentToStandalone(Attachment)
    case openAttachment(String)
    case attachmentOpened(String)
    case reloadData
    case processNoteSaveResult(note: Note)
    case setFieldValue(id: String, value: String)
    case setTags([Tag])
    case setTitle(NSAttributedString)
    case setAbstract(String)
    case saveCreator(ItemDetailState.Creator)
    case startEditing
    case toggleAbstractDetailCollapsed
    case updateDownload(AttachmentDownloader.Update)
    case updateAttachments(AttachmentFileDeletedNotification)
    case clearPreScrolledItemKey
}
