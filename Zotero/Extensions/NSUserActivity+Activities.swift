//
//  NSUserActivity+Activities.swift
//  Zotero
//
//  Created by Michal Rentka on 10.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RestoredStateData {
    let libraryId: LibraryIdentifier
    let collectionId: CollectionIdentifier
    let openItems: [OpenItem]
    let restoreMostRecentlyOpenedItem: Bool
}

extension NSUserActivity {
    private static let pdfId = "org.zotero.PDFActivity"
    private static let mainId = "org.zotero.MainActivity"

    private static let libraryIdKey = "libraryId"
    private static let collectionIdKey = "collectionId"
    private static let openItemsKey = "openItems"
    private static let restoreMostRecentlyOpenedItemKey = "restoreMostRecentlyOpenedItem"
    
    static func mainActivity(with openItems: [OpenItem]) -> NSUserActivity {
        let activity = NSUserActivity(activityType: self.mainId)
        activity.addUserInfoEntries(from: openItemsToUserInfo(openItems: openItems))
        let userInfo: [AnyHashable: Any] = [restoreMostRecentlyOpenedItemKey: false]
        activity.addUserInfoEntries(from: userInfo)
        return activity
    }

    static func pdfActivity(with openItems: [OpenItem], libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) -> NSUserActivity {
        let activity = NSUserActivity(activityType: self.pdfId)
        activity.addUserInfoEntries(from: openItemsToUserInfo(openItems: openItems))
        var userInfo: [AnyHashable: Any] = [libraryIdKey: libraryIdToString(libraryId), restoreMostRecentlyOpenedItemKey: true]
        if let collectionIdData = try? JSONEncoder().encode(collectionId) {
            userInfo[collectionIdKey] = collectionIdData
        }
        activity.addUserInfoEntries(from: userInfo)
        return activity
    }
    
    private static func openItemsToUserInfo(openItems: [OpenItem]) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [:]
        let encoder = JSONEncoder()
        userInfo[openItemsKey] = openItems.compactMap { try? encoder.encode($0) }
        return userInfo
    }
    
    private static func libraryIdToString(_ libraryId: LibraryIdentifier) -> String {
        switch libraryId {
        case .custom:
            return "myLibrary"
        case .group(let groupId):
            return "g:\(groupId)"
        }
    }

    private func stringToLibraryId(_ string: String) -> LibraryIdentifier? {
        guard !string.isEmpty else { return nil }

        if string == "myLibrary" {
            return .custom(.myLibrary)
        }

        if string[string.startIndex..<string.index(string.startIndex, offsetBy: 1)] == "g" {
            if let groupId = Int(String(string[string.index(string.startIndex, offsetBy: 2)..<string.endIndex])) {
                return .group(groupId)
            }
        }

        return nil
    }

    var restoredStateData: RestoredStateData? {
        guard let userInfo else { return nil }
        var libraryId: LibraryIdentifier = Defaults.shared.selectedLibrary
        var collectionId: CollectionIdentifier = Defaults.shared.selectedCollectionId
        var openItems: [OpenItem] = []
        var restoreMostRecentlyOpenedItem = false
        if let libraryString = userInfo[Self.libraryIdKey] as? String, let _libraryId = stringToLibraryId(libraryString) {
            libraryId = _libraryId
        }
        let decoder = JSONDecoder()
        if let collectionIdData = userInfo[Self.collectionIdKey] as? Data, let _collectionId = try? decoder.decode(CollectionIdentifier.self, from: collectionIdData) {
            collectionId = _collectionId
        }
        if let openItemsDataArray = userInfo[Self.openItemsKey] as? [Data] {
            openItems = openItemsDataArray.compactMap { try? decoder.decode(OpenItem.self, from: $0) }
        }
        if let _restoreMostRecentlyOpenedItem = userInfo[Self.restoreMostRecentlyOpenedItemKey] as? Bool {
            restoreMostRecentlyOpenedItem = _restoreMostRecentlyOpenedItem
        }
        // TODO: Migrate old pdf activity ("key", "libraryId") to "openItems"?
        return RestoredStateData(libraryId: libraryId, collectionId: collectionId, openItems: openItems, restoreMostRecentlyOpenedItem: restoreMostRecentlyOpenedItem)
    }
}
