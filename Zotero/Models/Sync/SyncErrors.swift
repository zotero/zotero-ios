//
//  SyncErrors.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

enum SyncError {
    struct ErrorData {
        let itemKeys: [String]?
        let libraryId: LibraryIdentifier

        static func from(libraryId: LibraryIdentifier) -> ErrorData {
            return ErrorData(itemKeys: nil, libraryId: libraryId)
        }

        static func from(syncObject: SyncObject, keys: [String], libraryId: LibraryIdentifier) -> ErrorData {
            switch syncObject {
            case .item:
                return ErrorData(itemKeys: keys, libraryId: libraryId)

            case .collection, .search, .settings, .trash:
                return ErrorData(itemKeys: nil, libraryId: libraryId)
            }
        }
    }

    case fatal(Fatal)
    case nonFatal(NonFatal)

    var fatal: Fatal? {
        switch self {
        case .fatal(let error): return error
        case .nonFatal: return nil
        }
    }

    var nonFatal: NonFatal? {
        switch self {
        case .fatal: return nil
        case .nonFatal(let error): return error
        }
    }

    enum Fatal: Error {
        case noInternetConnection
        case apiError(response: String, data: ErrorData)
        case dbError
        case groupSyncFailed
        case allLibrariesFetchFailed
        case uploadObjectConflict(data: ErrorData)
        case cantSubmitAttachmentItem(data: ErrorData)
        case permissionLoadingFailed
        case missingGroupPermissions
        case cancelled
        case serviceUnavailable
        case forbidden
    }

    enum NonFatal: Error {
        case versionMismatch(LibraryIdentifier)
        case apiError(response: String, data: ErrorData)
        case unknown(message: String, data: ErrorData)
        case schema(error: SchemaError, data: ErrorData)
        case parsing(error: Parsing.Error, data: ErrorData)
        case quotaLimit(LibraryIdentifier)
        case unchanged
        case attachmentMissing(key: String, libraryId: LibraryIdentifier, title: String)
        case annotationDidSplit(message: String, keys: Set<String>, libraryId: LibraryIdentifier)
        case insufficientSpace
        case webDavDeletion(count: Int, library: String)
        case webDavDeletionFailed(error: String, library: String)
        case webDavVerification(WebDavError.Verification)
        case webDavDownload(WebDavError.Download)

        var isVersionMismatch: Bool {
            switch self {
            case .versionMismatch:
                return true

            default:
                return false
            }
        }
    }
}

/// Errors for sync actions
/// - annotationNeededSplitting: Some annotations were too long and required splitting. Should repeat sync so that new annotations are submitted.
/// - attachmentAlreadyUploaded: Upload authorization is called and the backend returns that the attachment has already been uploaded.
/// - attachmentItemNotSubmitted: Upload action for attachment is called, but the attachments RItem has not been submitted yet.
/// - attachmentMissing: Attachment upload can't start because a file is missing.
/// - authorizationFailed: File upload authorization failed. Most cases require special handling.
/// - objectPreconditionError: 412 of individual object when submitted to backend.
/// - submitUpdateFailures: Failures of individual objects when submitting changes to backend
enum SyncActionError: Error {
    case annotationNeededSplitting(message: String, keys: Set<String>, libraryId: LibraryIdentifier)
    case attachmentAlreadyUploaded
    case attachmentItemNotSubmitted
    case attachmentMissing(key: String, libraryId: LibraryIdentifier, title: String)
    case authorizationFailed(statusCode: Int, response: String, hadIfMatchHeader: Bool)
    case objectPreconditionError
    case submitUpdateFailures(String)
}

extension SyncError.Fatal: Equatable {
    static func == (lhs: SyncError.Fatal, rhs: SyncError.Fatal) -> Bool {
        switch (lhs, rhs) {
        case (.noInternetConnection, .noInternetConnection),
             (.apiError, .apiError),
             (.dbError, .dbError),
             (.groupSyncFailed, .groupSyncFailed),
             (.allLibrariesFetchFailed, .allLibrariesFetchFailed),
             (.cancelled, .cancelled):
            return true

        default:
            return false
        }
    }
}

extension SyncError.NonFatal: Equatable {
    static func == (lhs: SyncError.NonFatal, rhs: SyncError.NonFatal) -> Bool {
        switch (lhs, rhs) {
        case (.versionMismatch, .versionMismatch):
            return true

        default:
            return false
        }
    }
}
