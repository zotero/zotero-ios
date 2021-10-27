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
        case apiError(String)
        case dbError
        case groupSyncFailed
        case allLibrariesFetchFailed
        case uploadObjectConflict
        case permissionLoadingFailed
        case missingGroupPermissions
        case cancelled
        case preconditionErrorCantBeResolved
        case cantResolveConflict
        case serviceUnavailable
    }

    enum NonFatal: Error {
        case versionMismatch(LibraryIdentifier)
        case apiError(String)
        case unknown(String)
        case schema(SchemaError)
        case parsing(Parsing.Error)
        case quotaLimit(LibraryIdentifier)
        case unchanged
        case attachmentMissing(key: String, title: String)
        case insufficientSpace

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
/// - attachmentItemNotSubmitted: Upload action for attachment is called, but the attachments RItem has not been submitted yet.
/// - attachmentAlreadyUploaded: Upload authorization is called and the backend returns that the attachment has already been uploaded.
/// - attachmentMissing: Attachment upload can't start because a file is missing.
enum SyncActionError: Error {
    case attachmentItemNotSubmitted,
         attachmentAlreadyUploaded,
         attachmentMissing(key: String, title: String),
         submitUpdateFailures(String)
}

enum PreconditionErrorType: Error {
    case objectConflict, libraryConflict
}

extension Error {
    var preconditionError: PreconditionErrorType? {
        if let error = self as? PreconditionErrorType {
            return error
        }
        if self.afError.flatMap({ $0.responseCode == 412 }) == true {
            return .libraryConflict
        }
        return nil
    }

    private var afError: AFError? {
        if let responseError = self as? AFResponseError {
            return responseError.error
        }
        if let alamoError = self as? AFError {
            return alamoError
        }
        return nil
    }
}

extension SyncError.Fatal: Equatable {
    static func ==(lhs: SyncError.Fatal, rhs: SyncError.Fatal) -> Bool {
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
    static func ==(lhs: SyncError.NonFatal, rhs: SyncError.NonFatal) -> Bool {
        switch (lhs, rhs) {
        case (.versionMismatch, .versionMismatch):
            return true
        default:
            return false
        }
    }
}
