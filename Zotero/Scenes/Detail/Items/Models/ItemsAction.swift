//
//  ItemsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

enum ItemsAction {
    case addAttachments([URL])
    case assignItemsToCollections(items: Set<String>, collections: Set<String>)
    case deleteItemsFromCollection(Set<String>)
    case deleteItems(Set<String>)
    case deselectItem(String)
    case filter([ItemsState.Filter])
    case loadInitialState
    case loadItemToDuplicate(String)
    case moveItems([String], String)
    case observingFailed
    case restoreItems(Set<String>)
    case saveNote(String, String, [Tag])
    case search(String)
    case selectItem(String)
    case toggleSelectionState
    case setSortField(ItemsSortType.Field)
    case startEditing
    case stopEditing
    case toggleSortOrder
    case trashItems(Set<String>)
    case cacheItemAccessory(item: RItem)
    case updateAttachments(AttachmentFileDeletedNotification)
    case updateDownload(AttachmentDownloader.Update)
    case openAttachment(attachment: Attachment, parentKey: String?)
    case updateKeys(items: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int])
    case quickCopyBibliography(RItem, UIViewController)
}
