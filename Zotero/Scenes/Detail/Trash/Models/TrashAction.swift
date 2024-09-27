//
//  TrashAction.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TrashAction {
    case attachmentOpened(String)
    case deleteObjects(Set<TrashKey>)
    case deselectItem(TrashKey)
    case disableFilter(ItemsFilter)
    case download(Set<TrashKey>)
    case emptyTrash
    case enableFilter(ItemsFilter)
    case loadData
    case openAttachment(attachment: Attachment, parentKey: String?)
    case removeDownloads(Set<TrashKey>)
    case restoreItems(Set<TrashKey>)
    case search(String)
    case setSortType(ItemsSortType)
    case selectItem(TrashKey)
    case startEditing
    case stopEditing
    case tagItem(itemKey: String, libraryId: LibraryIdentifier, tagNames: Set<String>)
    case toggleSelectionState
    case updateAttachments(AttachmentFileDeletedNotification)
    case updateDownload(update: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?)
}
