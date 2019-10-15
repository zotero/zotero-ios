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
        case .uploadAttachment(let upload):
            return upload.library
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
             .revertLibraryToOriginal(let library),
             .createUploadActions(let library):
            return library
        }
    }

    var requiresConflictReceiver: Bool {
        switch self {
        case .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .submitDeleteBatch, .submitWriteBatch, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .updateSchema, .uploadAttachment,
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
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .updateSchema,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return false
        }
    }

    var debugPermissionMessage: String {
        switch self {
        case .submitDeleteBatch(let batch):
            return "Delete \(batch.keys.count) \(batch.object) in \(batch.library.debugName)\n\(batch.keys)"
        case .submitWriteBatch(let batch):
            return "Write \(batch.parameters.count) changes for \(batch.object) in \(batch.library.debugName)\n\(batch.parameters)"
        case .uploadAttachment(let upload):
            return "Upload \(upload.filename).\(upload.extension) in \(upload.library.debugName)\n\(upload.file.createUrl().absoluteString)"
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .syncBatchToDb, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .updateSchema,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return "Unknown action"
        }
    }
}

extension SyncController.Library {
    var debugName: String {
        switch self {
        case .group(let groupId):
            return "Group (\(groupId))"
        case .user(_, let type):
            switch type {
            case .myLibrary:
                return "My Library"
            }
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
