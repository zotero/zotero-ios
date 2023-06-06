//
//  SyncControllerAction+Equatable.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

extension WriteBatch {
    public static func == (lhs: WriteBatch, rhs: WriteBatch) -> Bool {
        if lhs.libraryId != rhs.libraryId || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }

        if lhs.parameters.count != rhs.parameters.count {
            return false
        }

        for i in 0..<lhs.parameters.count {
            let lDict = lhs.parameters[i]
            let rDict = rhs.parameters[i]
            if !compare(lDict: lDict, rDict: rDict) {
                return false
            }
        }

        return true
    }

    private static func compare(lDict: [String: Any], rDict: [String: Any]) -> Bool {
        for key in lDict.keys {
            let lVal = lDict[key]
            let rVal = rDict[key]
            if "\(String(describing: lVal))" != "\(String(describing: rVal))" {
                return false
            }
        }
        return true
    }
}

extension DeleteBatch {
    public static func == (lhs: DeleteBatch, rhs: DeleteBatch) -> Bool {
        if lhs.libraryId != rhs.libraryId || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }
        return lhs.keys == rhs.keys
    }
}

extension DownloadBatch {
    public static func == (lhs: DownloadBatch, rhs: DownloadBatch) -> Bool {
        if lhs.libraryId != rhs.libraryId || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }

        if lhs.keys.count != rhs.keys.count {
            return false
        }
        for i in 0..<lhs.keys.count {
            if lhs.keys[i] != rhs.keys[i] {
                return false
            }
        }

        return true
    }
}
