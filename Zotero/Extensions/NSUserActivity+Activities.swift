//
//  NSUserActivity+Activities.swift
//  Zotero
//
//  Created by Michal Rentka on 10.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct RestoredStateData {
    let key: String
    let libraryId: LibraryIdentifier
    let collectionId: CollectionIdentifier
}

extension NSUserActivity {
    private static let pdfId = "org.zotero.PDFActivity"
    static let mainId = "org.zotero.MainActivity"

    static var mainActivity: NSUserActivity {
        return NSUserActivity(activityType: self.mainId)
    }

    static func pdfActivity(for key: String, libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) -> NSUserActivity {
        let activity = NSUserActivity(activityType: self.pdfId)
        var pdfUserInfo: [AnyHashable: Any] = ["key": key, "libraryId": libraryIdToString(libraryId)]
        if let collectionIdData = try? JSONEncoder().encode(collectionId) {
            pdfUserInfo["collectionId"] = collectionIdData
        }
        activity.addUserInfoEntries(from: pdfUserInfo)
        return activity
    }

    @discardableResult
    func set(title: String? = nil) -> NSUserActivity {
        self.title = title
        return self
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
        guard self.activityType == NSUserActivity.pdfId,
              let userInfo,
              let key = userInfo["key"] as? String,
              let libraryString = userInfo["libraryId"] as? String,
              let libraryId = stringToLibraryId(libraryString)
        else { return nil }
        var collectionId: CollectionIdentifier
        if let collectionIdData = userInfo["collectionId"] as? Data,
           let decodedCollectionId = try? JSONDecoder().decode(CollectionIdentifier.self, from: collectionIdData) {
            collectionId = decodedCollectionId
        } else {
            collectionId = Defaults.shared.selectedCollectionId
        }
        return RestoredStateData(key: key, libraryId: libraryId, collectionId: collectionId)
    }
}
