//
//  SyncControllerModels+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension SyncController.Library {
    var apiPath: String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
        case .user(let identifier, _):
            return "users/\(identifier)"
        }
    }

    var libraryId: LibraryIdentifier {
        switch self {
        case .group(let identifier):
            return .group(identifier)
        case .user(_, let type):
            return .custom(type)
        }
    }
}

extension SyncController.Object {
    var apiPath: String {
        switch self {
        case .group:
            return "groups"
        case .collection:
            return "collections"
        case .search:
            return "searches"
        case .item:
            return "items"
        case .trash:
            return "items/trash"
        case .tag:
            return "tags"
        }
    }
}

extension SyncController.Action {
    var library: SyncController.Library? {
        switch self {
        case .loadKeyPermissions, .updateSchema, .createLibraryActions:
            return nil
        case .syncBatchToDb(let batch):
            return batch.library
        case .submitWriteBatch(let batch):
            return batch.library
        case .submitDeleteBatch(let batch):
            return batch.library
        case .resolveDeletedGroup(let groupId, _),
             .resolveGroupMetadataWritePermission(let groupId, _),
             .deleteGroup(let groupId),
             .markGroupAsLocalOnly(let groupId):
            return .group(groupId)
        case .syncVersions(let library, _, _),
             .storeVersion(_, let library, _),
             .syncDeletions(let library, _),
             .syncSettings(let library, _),
             .storeSettingsVersion(_, let library),
             .resolveConflict(_, let library),
             .markChangesAsResolved(let library),
             .revertLibraryToOriginal(let library):
            return library
        }
    }

    var requiresConflictReceiver: Bool {
        switch self {
        case .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .submitDeleteBatch, .submitWriteBatch, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .updateSchema:
            return false
        }
    }
}

extension SyncController.WriteBatch: Equatable {
    static func ==(lhs: SyncController.WriteBatch, rhs: SyncController.WriteBatch) -> Bool {
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
            // TODO: - compare values
        }
        return true
    }
}

extension SyncController.DeleteBatch: Equatable {
    public static func ==(lhs: SyncController.DeleteBatch, rhs: SyncController.DeleteBatch) -> Bool {
        if lhs.library != rhs.library || lhs.object != rhs.object || lhs.version != rhs.version {
            return false
        }
        return lhs.keys == rhs.keys
    }
}

extension SyncController.DownloadBatch: Equatable {
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

extension SyncError: Equatable {
    static func ==(lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.noInternetConnection, .noInternetConnection),
             (.apiError, .apiError),
             (.dbError, .dbError),
             (.versionMismatch, .versionMismatch),
             (.groupSyncFailed, .groupSyncFailed),
             (.allLibrariesFetchFailed, .allLibrariesFetchFailed),
             (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}
