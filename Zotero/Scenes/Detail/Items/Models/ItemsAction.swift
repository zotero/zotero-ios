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
    case deleteItemsFromCollection(Set<String>)
    case deleteItems(Set<String>)
    case deselectItem(String)
    case download(Set<String>)
    case filter([ItemsState.Filter])
    case loadInitialState
    case loadItemToDuplicate(String)
    case moveItems([String], String)
    case observingFailed
    case removeDownloads(Set<String>)
    case restoreItems(Set<String>)
    case saveNote(String, String, [Tag])
    case search(String)
    case initialSearch(String)
    case selectItem(String)
    case setSortField(ItemsSortType.Field)
    case setSortOrder(Bool)
    case startEditing
    case stopEditing
    case toggleSelectionState
    case trashItems(Set<String>)
    case cacheItemAccessory(item: RItem)
    case updateAttachments(AttachmentFileDeletedNotification)
    case updateDownload(update: AttachmentDownloader.Update, batchData: ItemsState.DownloadBatchData?)
    case openAttachment(attachment: Attachment, parentKey: String?)
    case attachmentOpened(String)
    case updateKeys(items: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int])
    case quickCopyBibliography(Set<String>, LibraryIdentifier, WKWebView)
    case startSync
    case emptyTrash
}
