//
//  SyncErrors.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire

enum SyncError: Error {
    case cancelled
    case noInternetConnection
    case apiError
    case dbError
    case versionMismatch
    case groupSyncFailed(Error)
    case allLibrariesFetchFailed(Error)
    case uploadObjectConflict
    case permissionLoadingFailed
    case missingGroupPermissions
}

/// Errors for sync actions
/// - attachmentItemNotSubmitted: Upload action for attachment is called, but the attachments RItem has not been submitted yet.
/// - attachmentAlreadyUploaded: Upload authorization is called and the backend returns that the attachment has already been uploaded.
/// - attachmentMissing: Attachment upload can't start because a file is missing.
enum SyncActionError: Error {
    case attachmentItemNotSubmitted,
         attachmentAlreadyUploaded,
         attachmentMissing
}

enum PreconditionErrorType: Error {
    case objectConflict, libraryConflict
}

extension Error {
    var isMismatchError: Bool {
        return (self as? SyncError) == .versionMismatch
    }

    var preconditionError: PreconditionErrorType? {
        if let error = self as? PreconditionErrorType, error == .objectConflict {
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
