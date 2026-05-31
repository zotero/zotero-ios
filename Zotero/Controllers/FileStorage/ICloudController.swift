//
//  ICloudController.swift
//  Zotero
//
//  Created by Claude on 30.05.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift
import ZIPFoundation

enum ICloudError {
    enum Verification: Swift.Error {
        case accountUnavailable
        case containerUnavailable
        case probeFailed

        var message: String {
            switch self {
            case .accountUnavailable:
                return L10n.Errors.Settings.Icloud.accountUnavailable

            case .containerUnavailable:
                return L10n.Errors.Settings.Icloud.containerUnavailable

            case .probeFailed:
                return L10n.Errors.Settings.Icloud.probeFailed
            }
        }
    }

    enum Download: Swift.Error {
        case itemPropInvalid(String)
    }

    static func message(for error: Error) -> String {
        if let error = error as? ICloudError.Verification {
            return error.message
        }
        return error.localizedDescription
    }
}

/// `FileSyncBackend` backed by the app's iCloud Drive ubiquitous container. Keeps the `<key>.zip` + `<key>.prop` layout (identical to
/// WebDAV/desktop), so a file uploaded by another client lands in the same logical place and the mtime/hash conflict logic ports directly.
/// iCloud only moves the bytes; the data layer (file versions) is registered with the Zotero API by the caller, exactly like WebDAV.
final class ICloudController: FileSyncBackend {
    private enum MetadataResult {
        case unchanged
        case mtimeChanged(Int)
        case changed
        case new
    }

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    let transport: ICloudTransport

    init(dbStorage: DbStorage, fileStorage: FileStorage, transport: ICloudTransport) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.transport = transport
    }

    var type: FileSyncType { return .iCloud }

    var isVerified: Bool { return Defaults.shared.iCloudVerified }

    var isAvailable: Bool { return transport.isAccountAvailable }

    func resetVerification() {
        Defaults.shared.iCloudVerified = false
    }

    func verify(queue: DispatchQueue) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            guard transport.isAccountAvailable else {
                subscriber(.failure(ICloudError.Verification.accountUnavailable))
                return Disposables.create()
            }
            do {
                _ = try transport.storageDirectory()
            } catch {
                subscriber(.failure(ICloudError.Verification.containerUnavailable))
                return Disposables.create()
            }
            subscriber(.success(()))
            return Disposables.create()
        }
        .flatMap { [weak self] _ -> Single<()> in
            guard let self else { return .error(ICloudError.Verification.containerUnavailable) }
            // Probe: write + read + delete a small file to confirm read/write access.
            let probeName = ".zotero-probe"
            guard let data = "ok".data(using: .utf8) else { return .error(ICloudError.Verification.probeFailed) }
            return transport.write(data: data, toItemNamed: probeName)
                .flatMap { self.transport.readData(fromItemNamed: probeName) }
                .flatMap { read -> Single<()> in
                    guard read == data else { return .error(ICloudError.Verification.probeFailed) }
                    return self.transport.remove(itemNamed: probeName).flatMap { _ in .just(()) }
                }
        }
        .do(onSuccess: { _ in
            Defaults.shared.iCloudVerified = true
            DDLogInfo("ICloudController: verified")
        }, onError: { error in
            DDLogError("ICloudController: verification failed - \(error)")
            Defaults.shared.iCloudVerified = false
        })
    }

    func download(key: String, file: File, queue: DispatchQueue) -> Observable<Progress> {
        let zipName = key + ".zip"
        let localZip = file.copy(withExt: "zip")
        return transport.materialize(name: zipName, queue: queue)
            .concat(Observable.deferred { [weak self] () -> Observable<Progress> in
                guard let self else { return .empty() }
                return copyZipLocally(zipName: zipName, localZip: localZip).asObservable().flatMap { _ in Observable<Progress>.empty() }
            })

        func copyZipLocally(zipName: String, localZip: File) -> Single<()> {
            return Single.create { [weak self] subscriber in
                guard let self else { return Disposables.create() }
                do {
                    try fileStorage.createDirectories(for: localZip)
                    try? fileStorage.remove(localZip)
                } catch let error {
                    subscriber(.failure(error))
                    return Disposables.create()
                }
                return transport.copyItem(named: zipName, to: localZip.createUrl())
                    .subscribe(onSuccess: { subscriber(.success(())) }, onFailure: { subscriber(.failure($0)) })
            }
        }
    }

    func prepareForUpload(key: String, mtime: Int, hash: String, file: File, queue: DispatchQueue) -> Single<FileUploadResult> {
        DDLogInfo("ICloudController: prepare for upload \(key)")
        return checkMetadata(key: key, mtime: mtime, hash: hash, queue: queue)
            .flatMap { [weak self] result -> Single<FileUploadResult> in
                guard let self else { return .error(ICloudError.Verification.containerUnavailable) }
                switch result {
                case .unchanged:
                    return .just(.exists)

                case .mtimeChanged(let remoteMtime):
                    return updateMtime(remoteMtime, key: key, queue: queue).flatMap { .just(.exists) }

                case .new:
                    return zip(file: file, key: key).flatMap { .just(.new($0)) }

                case .changed:
                    return removeExistingProp(key: key)
                        .flatMap { self.zip(file: file, key: key) }
                        .flatMap { .just(.new($0)) }
                }
            }
    }

    func upload(key: String, file: File, mtime: Int, hash: String, queue: DispatchQueue) -> Single<()> {
        DDLogInfo("ICloudController: upload \(key)")
        return transport.copy(localFile: file.createUrl(), toItemNamed: key + ".zip")
    }

    func finishUpload(key: String, result: Result<(Int, String), Swift.Error>, file: File?, queue: DispatchQueue) -> Single<()> {
        switch result {
        case .success((let mtime, let hash)):
            DDLogInfo("ICloudController: finish successful upload \(key)")
            return uploadMetadata(key: key, mtime: mtime, hash: hash)
                .flatMap { [weak self] _ in
                    self?.remove(file: file) ?? .just(())
                }

        case .failure(let error):
            DDLogError("ICloudController: finish failed upload \(key) - \(error)")
            return remove(file: file)
        }
    }

    func delete(keys: [String], queue: DispatchQueue) -> Single<FileDeletionResult> {
        let singles = keys.map { key -> Single<(String, Bool, Bool)> in
            Single.zip(transport.remove(itemNamed: key + ".zip"), transport.remove(itemNamed: key + ".prop"))
                .map { (key, $0.0, $0.1) }
                .catch { _ in .just((key, false, false)) }
        }
        guard !singles.isEmpty else {
            return .just(FileDeletionResult(succeeded: [], missing: [], failed: []))
        }
        return Single.zip(singles).map { results in
            var succeeded: Set<String> = []
            var missing: Set<String> = []
            for (key, zipRemoved, propRemoved) in results {
                if zipRemoved || propRemoved {
                    succeeded.insert(key)
                } else {
                    // Nothing to remove — treat as already gone.
                    missing.insert(key)
                }
            }
            return FileDeletionResult(succeeded: succeeded, missing: missing, failed: [])
        }
    }

    /// iOS analog of `purgeOrphanedStorageFiles`: removes container `<KEY>.zip`/`.prop` whose key has no surviving attachment.
    func purgeOrphans(validKeys: Set<String>, queue: DispatchQueue) -> Single<()> {
        return transport.listItemNames().flatMap { [weak self] names -> Single<()> in
            guard let self else { return .just(()) }
            var orphanKeys: Set<String> = []
            for name in names {
                guard name.hasSuffix(".zip") || name.hasSuffix(".prop") else { continue }
                let key = String(name.dropLast(name.hasSuffix(".zip") ? 4 : 5))
                guard key.count == KeyGenerator.length, !validKeys.contains(key) else { continue }
                orphanKeys.insert(key)
            }
            guard !orphanKeys.isEmpty else { return .just(()) }
            DDLogInfo("ICloudController: purge \(orphanKeys.count) orphaned files")
            return delete(keys: Array(orphanKeys), queue: queue).flatMap { _ in .just(()) }
        }
    }

    // MARK: - Metadata

    private func checkMetadata(key: String, mtime: Int, hash: String, queue: DispatchQueue) -> Single<MetadataResult> {
        return transport.readData(fromItemNamed: key + ".prop")
            .flatMap { data -> Single<MetadataResult> in
                guard let data, !data.isEmpty else { return .just(.new) }

                let delegate = WebDavPropParserDelegate()
                let parser = XMLParser(data: data)
                parser.delegate = delegate

                guard parser.parse(), let remoteMtime = delegate.mtime, let remoteHash = delegate.fileHash else {
                    DDLogError("ICloudController: \(key) prop invalid")
                    return .error(ICloudError.Download.itemPropInvalid(String(data: data, encoding: .utf8) ?? ""))
                }

                if hash == remoteHash {
                    return .just(mtime == remoteMtime ? .unchanged : .mtimeChanged(remoteMtime))
                }
                return .just(.changed)
            }
    }

    private func uploadMetadata(key: String, mtime: Int, hash: String) -> Single<()> {
        let prop = "<properties version=\"1\"><mtime>\(mtime)</mtime><hash>\(hash)</hash></properties>"
        guard let data = prop.data(using: .utf8) else { return .error(ICloudError.Download.itemPropInvalid(prop)) }
        return transport.write(data: data, toItemNamed: key + ".prop")
    }

    private func removeExistingProp(key: String) -> Single<()> {
        return transport.remove(itemNamed: key + ".prop").flatMap { _ in .just(()) }
    }

    private func updateMtime(_ mtime: Int, key: String, queue: DispatchQueue) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                try dbStorage.perform(request: StoreMtimeForAttachmentDbRequest(mtime: mtime, key: key, libraryId: .custom(.myLibrary)), on: queue)
                subscriber(.success(()))
            } catch let error {
                DDLogError("ICloudController: can't update mtime - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    // MARK: - Files

    private func zip(file: File, key: String) -> Single<File> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            DDLogInfo("ICloudController: zip file for upload \(key)")
            do {
                let tmpFile = Files.temporaryZipUploadFile(key: key)
                try fileStorage.createDirectories(for: tmpFile)
                try? fileStorage.remove(tmpFile)
                try FileManager.default.zipItem(at: file.createUrl(), to: tmpFile.createUrl())
                subscriber(.success(tmpFile))
            } catch let error {
                DDLogError("ICloudController: can't zip file - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    private func remove(file: File?) -> Single<()> {
        return Single.create { [weak self] subscriber in
            if let file { try? self?.fileStorage.remove(file) }
            subscriber(.success(()))
            return Disposables.create()
        }
    }
}
