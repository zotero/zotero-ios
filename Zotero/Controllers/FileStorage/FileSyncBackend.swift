//
//  FileSyncBackend.swift
//  Zotero
//
//  Created by Claude on 30.05.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

/// Result of `prepareForUpload`. The `<key>.zip`/`<key>.prop` scheme is shared by all non-ZFS backends.
/// - `exists`: the remote already has an up-to-date copy (matching mtime + hash), no upload needed.
/// - `new`: the file (a freshly created zip) needs to be uploaded.
enum FileUploadResult {
    case exists
    case new(File)
}

/// Aggregated result of a deferred remote deletion pass. (`WebDavDeletionResult` is a typealias of this.)
struct FileDeletionResult {
    let succeeded: Set<String>
    let missing: Set<String>
    let failed: Set<String>
}

/// Backend-agnostic contract for the file-storage layer. The active backend moves the *bytes* of attachment files; the *data* layer
/// (which item has which file version) is always server-mediated through the Zotero API by the caller.
///
/// This protocol captures only the operations that are genuinely uniform across backends — selection, verification and deferred deletion.
/// The upload/download *transport* differs fundamentally per backend (WebDAV/ZFS use a background `URLSession` driven by
/// `AttachmentDownloader`/`BackgroundUploader`; iCloud uses the OS ubiquity daemon via `NSFileCoordinator`/`NSMetadataQuery`), so those
/// flows stay on the concrete controllers and call sites branch on `FileSyncType`.
protocol FileSyncBackend: AnyObject {
    /// The backend this controller represents (never `.zotero`; ZFS is the implicit inline path).
    var type: FileSyncType { get }
    /// Whether the backend has been verified and is ready to use.
    var isVerified: Bool { get }

    /// Verifies the backend is reachable/usable (credentials, container, account, writability). Marks it verified on success.
    func verify(queue: DispatchQueue) -> Single<()>
    /// Clears the verified state.
    func resetVerification()
    /// Removes `<key>.zip`/`<key>.prop` (and placeholders) for the given keys.
    func delete(keys: [String], queue: DispatchQueue) -> Single<FileDeletionResult>
}

/// Resolves the active file-storage backend from `Defaults.shared.fileSyncType`. Returns `nil` for `.zotero` (ZFS inline path).
final class FileSyncBackendProvider {
    private unowned let webDavController: WebDavController
    private unowned let iCloudController: ICloudController

    init(webDavController: WebDavController, iCloudController: ICloudController) {
        self.webDavController = webDavController
        self.iCloudController = iCloudController
    }

    /// The active backend, or `nil` when ZFS (Zotero Storage) should be used inline.
    func current() -> FileSyncBackend? {
        return controller(for: Defaults.shared.fileSyncType)
    }

    func controller(for type: FileSyncType) -> FileSyncBackend? {
        switch type {
        case .zotero:
            return nil

        case .webDav:
            return webDavController

        case .iCloud:
            return iCloudController
        }
    }
}
