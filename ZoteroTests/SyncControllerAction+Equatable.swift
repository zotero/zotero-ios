//
//  SyncControllerAction+Equatable.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 20/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@testable import Zotero

extension SyncController.WriteBatch {
    public static func ==(lhs: SyncController.WriteBatch, rhs: SyncController.WriteBatch) -> Bool {
        if lhs.library != rhs.library || lhs.object != rhs.object || lhs.version != rhs.version {
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

extension SyncController.DeleteBatch {
    public static func ==(lhs: SyncController.DeleteBatch, rhs: SyncController.DeleteBatch) -> Bool {
        if lhs.library != rhs.library || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }
        return lhs.keys == rhs.keys
    }
}

extension SyncController.DownloadBatch {
    public static func ==(lhs: SyncController.DownloadBatch, rhs: SyncController.DownloadBatch) -> Bool {
        if lhs.library != rhs.library || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }

        if lhs.keys.count != rhs.keys.count {
            return false
        }
        for i in 0..<lhs.keys.count {
            if let lInt = lhs.keys[i] as? Int, let rInt = rhs.keys[i] as? Int {
                if lInt != rInt {
                    return false
                }
            } else if let lStr = lhs.keys[i] as? String, let rStr = rhs.keys[i] as? String {
                if lStr != rStr {
                    return false
                }
            } else {
                return false
            }
        }

        return true
    }
}
