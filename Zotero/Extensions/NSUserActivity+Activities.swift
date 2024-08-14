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

    static func myLibrary() -> Self {
        .init(libraryId: .custom(.myLibrary), collectionId: .custom(.all), openItems: [], restoreMostRecentlyOpenedItem: false)
    }
}

extension NSUserActivity {
    public static let deprecatedPdfId = "org.zotero.PDFActivity"
    public static let contentContainerId = "org.zotero.ContentContainerActivity"
    public static let mainId = "org.zotero.MainActivity"

    private static let libraryIdKey = "libraryId"
    private static let collectionIdKey = "collectionId"
    private static let openItemsKey = "openItems"
    private static let restoreMostRecentlyOpenedItemKey = "restoreMostRecentlyOpenedItem"
    
    static func mainActivity() -> NSUserActivity {
        return NSUserActivity(activityType: self.mainId)
            .addUserInfoEntries(openItems: [])
            .addUserInfoEntries(restoreMostRecentlyOpened: false)
    }

    static func contentActivity(with openItems: [OpenItem], libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) -> NSUserActivity {
        return NSUserActivity(activityType: self.contentContainerId)
            .addUserInfoEntries(openItems: openItems)
            .addUserInfoEntries(libraryId: libraryId, collectionId: collectionId, restoreMostRecentlyOpened: true)
    }
    
    @discardableResult
    func addUserInfoEntries(openItems: [OpenItem]) -> Self {
        var userInfo: [AnyHashable: Any] = [:]
        let encoder = JSONEncoder()
        userInfo[Self.openItemsKey] = openItems.compactMap { try? encoder.encode($0) }
        addUserInfoEntries(from: userInfo)
        return self
    }

    @discardableResult
    func set(title: String? = nil) -> Self {
        self.title = title
        return self
    }

    @discardableResult
    func addUserInfoEntries(libraryId: LibraryIdentifier? = nil, collectionId: CollectionIdentifier? = nil, restoreMostRecentlyOpened: Bool = false) -> Self {
        var userInfo: [AnyHashable: Any] = [:]
        if let libraryId {
            userInfo[Self.libraryIdKey] = libraryIdToString(libraryId)
        }
        if let collectionId, let collectionIdData = try? JSONEncoder().encode(collectionId) {
            userInfo[Self.collectionIdKey] = collectionIdData
        }
        userInfo[Self.restoreMostRecentlyOpenedItemKey] = restoreMostRecentlyOpened
        addUserInfoEntries(from: userInfo)
        return self

        func libraryIdToString(_ libraryId: LibraryIdentifier) -> String {
            switch libraryId {
            case .custom:
                return "myLibrary"
            case .group(let groupId):
                return "g:\(groupId)"
            }
        }
    }

    var restoredStateData: RestoredStateData? {
        guard let userInfo else { return nil }

        switch activityType {
        case Self.contentContainerId:
            return restoreContentContainer()

        case Self.deprecatedPdfId:
            return restoreDeprecatedPdf()

        default:
            return nil
        }

        func stringToLibraryId(_ string: String) -> LibraryIdentifier? {
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

        func restoreContentContainer() -> RestoredStateData {
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
            return RestoredStateData(libraryId: libraryId, collectionId: collectionId, openItems: openItems, restoreMostRecentlyOpenedItem: restoreMostRecentlyOpenedItem)
        }

        func restoreDeprecatedPdf() -> RestoredStateData? {
            guard let key = userInfo["key"] as? String else { return nil }
            var libraryId: LibraryIdentifier = Defaults.shared.selectedLibrary
            var collectionId: CollectionIdentifier = Defaults.shared.selectedCollectionId
            if let libraryString = userInfo["libraryId"] as? String, let _libraryId = stringToLibraryId(libraryString) {
                libraryId = _libraryId
            }
            if let collectionIdData = userInfo["collectionId"] as? Data, let decodedCollectionId = try? JSONDecoder().decode(CollectionIdentifier.self, from: collectionIdData) {
                collectionId = decodedCollectionId
            }
            let item = OpenItem(kind: .pdf(libraryId: libraryId, key: key), userIndex: 0)
            return RestoredStateData(libraryId: libraryId, collectionId: collectionId, openItems: [item], restoreMostRecentlyOpenedItem: true)
        }
    }
}
