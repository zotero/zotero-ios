//
//  ItemsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum ItemsAction {
    case addAttachments([URL])
    case assignSelectedItemsToCollections(Set<String>)
    case deleteSelectedItems
    case deselectItem(String)
    case loadInitialState
    case loadItemToDuplicate(String)
    case moveItems([String], String)
    case observingFailed
    case restoreSelectedItems
    case saveNote(String?, String)
    case search(String)
    case selectItem(String)
    case toggleSelectionState
    case setSortField(ItemsSortType.Field)
    case startEditing
    case stopEditing
    case toggleSortOrder
    case trashSelectedItems
    case cacheAttachment(item: RItem)
    case cacheAttachmentUpdates(results: Results<RItem>, updates: [Int])
    case updateAttachments(AttachmentFileDeletedNotification)
    case updateDownload(FileDownloader.Update)
    case openAttachment(key: String, parentKey: String)
}
