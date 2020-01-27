//
//  SyncControllerModels+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension LibraryIdentifier {
    func apiPath(userId: Int) -> String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
        case .custom:
            return "users/\(userId)"
        }
    }

    var debugName: String {
        switch self {
        case .group(let groupId):
            return "Group (\(groupId))"
        case .custom(let type):
            switch type {
            case .myLibrary:
                return "My Library"
            }
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
    var libraryId: LibraryIdentifier? {
        switch self {
        case .loadKeyPermissions, .createLibraryActions:
            return nil
        case .syncBatchToDb(let batch):
            return batch.libraryId
        case .submitWriteBatch(let batch):
            return batch.libraryId
        case .submitDeleteBatch(let batch):
            return batch.libraryId
        case .uploadAttachment(let upload):
            return upload.libraryId
        case .resolveDeletedGroup(let groupId, _),
             .resolveGroupMetadataWritePermission(let groupId, _),
             .deleteGroup(let groupId),
             .markGroupAsLocalOnly(let groupId):
            return .group(groupId)
        case .syncVersions(let libraryId, _, _),
             .storeVersion(_, let libraryId, _),
             .syncDeletions(let libraryId, _),
             .syncSettings(let libraryId, _),
             .storeSettingsVersion(_, let libraryId),
             .resolveConflict(_, let libraryId),
             .markChangesAsResolved(let libraryId),
             .revertLibraryToOriginal(let libraryId),
             .createUploadActions(let libraryId):
            return libraryId
        }
    }

    var requiresConflictReceiver: Bool {
        switch self {
        case .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .submitDeleteBatch, .submitWriteBatch, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .uploadAttachment,
             .createUploadActions:
            return false
        }
    }

    var requiresDebugPermissionPrompt: Bool {
        switch self {
        case .submitDeleteBatch, .submitWriteBatch, .uploadAttachment:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return false
        }
    }

    var debugPermissionMessage: String {
        switch self {
        case .submitDeleteBatch(let batch):
            return "Delete \(batch.keys.count) \(batch.object) in \(batch.libraryId.debugName)\n\(batch.keys)"
        case .submitWriteBatch(let batch):
            return "Write \(batch.parameters.count) changes for \(batch.object) in \(batch.libraryId.debugName)\n\(batch.parameters)"
        case .uploadAttachment(let upload):
            return "Upload \(upload.filename).\(upload.extension) in \(upload.libraryId.debugName)\n\(upload.file.createUrl().absoluteString)"
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return "Unknown action"
        }
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
