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
}

extension NSUserActivity {
    private static let pdfId = "org.zotero.PDFActivity"
    private static let mainId = "org.zotero.MainActivity"

    static var mainActivity: NSUserActivity {
        return NSUserActivity(activityType: self.mainId)
    }

    static func pdfActivity(for key: String, libraryId: LibraryIdentifier) -> NSUserActivity {
        let activity = NSUserActivity(activityType: self.pdfId)
        activity.addUserInfoEntries(from: ["key": key, "libraryId": self.libraryIdToString(libraryId)])
        return activity
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
              let key = self.userInfo?["key"] as? String, let libraryString = self.userInfo?["libraryId"] as? String, let libraryId = self.stringToLibraryId(libraryString) else { return nil }
        return RestoredStateData(key: key, libraryId: libraryId)
    }
}
