//
//  ItemsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RealmSwift

enum ItemsAction {
    case addAttachments([URL])
    case assignItemsToCollections(items: Set<String>, collections: Set<String>)
    case cacheItemTitle(key: String, title: String)
    case clearTitleCache
    case deleteItemsFromCollection(Set<String>)
    case deselectItem(String)
    case download(Set<String>)
    case enableFilter(ItemsFilter)
    case disableFilter(ItemsFilter)
    case loadInitialState
    case loadItemToDuplicate(String)
    case moveItems(keys: Set<String>, toItemKey: String)
    case observingFailed
    case removeDownloads(Set<String>)
    case search(String)
    case selectItem(String)
    case setSortField(ItemsSortType.Field)
    case setSortOrder(Bool)
    case startEditing
    case stopEditing
    case tagItem(itemKey: String, libraryId: LibraryIdentifier, tagNames: Set<String>)
    case toggleSelectionState
    case trashItems(Set<String>)
    case cacheItemAccessory(item: RItem)
    case updateAttachments(AttachmentFileDeletedNotification)
    case updateDownload(update: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?)
    case updateIdentifierLookup(update: IdentifierLookupController.Update, batchData: ItemsState.IdentifierLookupBatchData)
    case updateRemoteDownload(update: RemoteAttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?)
    case openAttachment(attachment: Attachment, parentKey: String?)
    case attachmentOpened(String)
    case updateKeys(items: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int])
}
