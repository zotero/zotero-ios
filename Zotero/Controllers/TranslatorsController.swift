//
//  TranslatorsController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift
import Zip

typealias TranslatorInfo = [String: Any]

class TranslatorsController {
    enum UpdateType: Int {
        case manual = 1
        case initial = 2
        case startup = 3
        case notification = 4
    }

    enum Error: Swift.Error {
        case expired, bundleMissing, cantParseIndexFile
    }

    @UserDefault(key: "TranslatorLastCommitHash", defaultValue: "")
    private var lastCommitHash: String
    @UserDefault(key: "TranslatorLastTimestamp", defaultValue: 0)
    private var lastTimestamp: Double
    private var lastDate: Date {
        return Date(timeIntervalSince1970: self.lastTimestamp)
    }

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let dbStorage: DbStorage

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        do {
            try fileStorage.createDirectories(for: Files.translatorsDbFile)
        } catch let error {
            fatalError("TranslatorsController: could not create db directories - \(error)")
        }

        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = RealmDbStorage(url: Files.translatorsDbFile.createUrl())
        self.disposeBag = DisposeBag()
    }

    func update() {
        self.updateFromBundle()
            .flatMap {
                return self.updateFromRepo()
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { _ in

            }, onError: { error in

            })
            .disposed(by: self.disposeBag)
    }

    private func updateFromBundle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(Error.expired))
                return Disposables.create()
            }

            do {
                if try self.commitHashDidChange() {
                    try self.syncTranslatorsWithBundledData()
                }
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }

    private func syncTranslatorsWithBundledData() throws {
        let metadata = try self.loadTranslatorsIndex()
        let (updated, deleted) = try self.dbStorage.createCoordinator().perform(request: SyncTranslatorsDbRequest(metadata: metadata))
        
        // TODO: - delete "deleted" filenames from translators folder

        guard !updated.isEmpty else { return }

        // TODO: - unzip bundled zip
        // TODO: - copy "updated" filenames from unzipped folder to translators folder
    }

    private func loadTranslatorsIndex() throws -> [TranslatorMetadata] {
        guard let indexFilePath = Bundle.main.path(forResource: "index", ofType: "json") else {
            throw Error.bundleMissing
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: indexFilePath))
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] else {
            throw Error.cantParseIndexFile
        }
        return json.compactMap({ TranslatorMetadata(id: $0.key, data: $0.value) })
    }

    private func loadBundledData() throws {
        guard let zipUrl = Bundle.main.path(forResource: "translators", ofType: "zip").flatMap({ URL(fileURLWithPath: $0) }) else {
            throw Error.bundleMissing
        }
        try Zip.unzipFile(zipUrl, destination: Files.tmpTranslators.createUrl(), overwrite: true, password: nil)
    }

    private func commitHashDidChange() throws -> Bool {
        if self.lastCommitHash == "" {
            return true
        }

        guard let path = Bundle.main.path(forResource: "commit_hash", ofType: "txt"),
              let hash = try? String(contentsOf: URL(fileURLWithPath: path)) else {
            throw Error.bundleMissing
        }

        return hash != self.lastCommitHash
    }

    func updateFromRepo() -> Single<()> {
        return Single.just(())
    }

    func resetToBundle() {

    }

    func translators() -> Single<[TranslatorInfo]> {
//        if TranslatorsController.needsReload {
//            return self.download()
//                       .do(onSuccess: {
//                           TranslatorsController.needsReload = false
//                       })
//                       .flatMap  { [weak self] in
//                           guard let `self` = self else { return Single.error(Error.expired) }
//                           return self.loadLocalData()
//                       }
//        }
//
//        if self.fileStorage.has(Files.translators) {
//            return self.loadLocalData()
//        } else {
//            return self.loadBundledData()
//        }
        return Single.just([])
    }

//    private func download() -> Single<()> {
//        return self.apiClient.download(request: TranslatorsRequest())
//                             .flatMap { request in
//                                return request.rx.response()
//                             }
//                             .asSingle()
//                             .flatMap { [weak self] _ in
//                                 guard let `self` = self else { return Single.error(Error.expired) }
//                                 return self.unzipTranslators()
//                             }
//    }
//
//    /// Unzip translators if possible. This method tries to:
//    /// 1. Unzip files into temporary directory
//    /// 2. Remove original translators directory if available
//    /// 3. Move temporary directory to original destination
//    /// 4. Cleanup zip file
//    /// If anything breaks, it tries to cleanup temporary directory and zip file.
//    /// - returns: Single which reports that translators have been successfully unpacked, Error otherwise.
//    private func unzipTranslators() -> Single<()> {
//        let translators = Files.translators
//        let zip = Files.translatorZip
//        let unpacked = Files.translatorsUnpacked
//
//        do {
//            try Zip.unzipFile(zip.createUrl(), destination: unpacked.createUrl(), overwrite: true, password: nil)
//            if self.fileStorage.has(translators) {
//                try self.fileStorage.remove(translators)
//            }
//            // Unzipping creates a folder inside our unpacked folder, find File and move its contents to translators
//            let unpackedFiles: [File] = try self.fileStorage.contentsOfDirectory(at: unpacked)
//            if unpackedFiles.isEmpty {
//                throw Error.unpackedFileEmpty
//            } else if unpackedFiles.count == 1, let content = unpackedFiles.first {
//                try self.fileStorage.move(from: content, to: translators)
//                try self.fileStorage.remove(unpacked)
//            } else {
//                if unpackedFiles.contains(where: { $0.ext == "js" }) {
//                    try self.fileStorage.move(from: unpacked, to: translators)
//                } else {
//                    throw Error.unpackedUnknownContent
//                }
//            }
//            try self.fileStorage.remove(zip)
//            return Single.just(())
//        } catch let error {
//            try? self.fileStorage.remove(zip)
//            try? self.fileStorage.remove(unpacked)
//            return Single.error(error)
//        }
//    }
//
//    private func loadLocalData() -> Single<[TranslatorInfo]> {
//        return self.loadTranslators(from: Files.translators)
//    }
//
//    private func loadBundledData() -> Single<[TranslatorInfo]> {
//        guard let url = Bundle.main.url(forResource: "translators",
//                                        withExtension: nil,
//                                        subdirectory: "translation/modules/zotero") else {
//            return Single.error(Error.bundleMissing)
//        }
//        return self.loadTranslators(from: Files.file(from: url))
//    }
//
//    private func loadTranslators(from file: File) -> Single<[TranslatorInfo]> {
//        do {
//            let contents: [File] = try self.fileStorage.contentsOfDirectory(at: file)
//            let translators = contents.compactMap({ self.loadTranslatorInfo(from: $0) })
//            return Single.just(translators)
//        } catch let error {
//            DDLogError("TranslatorController: error - \(error)")
//            return Single.error(error)
//        }
//    }
//
//    private func loadTranslatorInfo(from file: File) -> TranslatorInfo? {
//        guard file.ext == "js" else { return nil }
//
//        do {
//            let data = try self.fileStorage.read(file)
//
//            guard let string = String(data: data, encoding: .utf8),
//                  let endingIndex = self.metadataIndex(from: string),
//                  let metadataData = string[string.startIndex..<endingIndex].data(using: .utf8),
//                  var metadata = try JSONSerialization.jsonObject(with: metadataData,
//                                                                  options: .allowFragments) as? [String: Any] else {
//                throw Error.incompatibleString
//            }
//
//            metadata["code"] = string
//
//            return metadata
//        } catch let error {
//            DDLogError("TranslatorsController: cant' read data from \(file.createUrl()) - \(error)")
//            return nil
//        }
//    }
//
//    private func metadataIndex(from string: String) -> String.Index? {
//        var count = 0
//        for (index, character) in string.enumerated() {
//            if character == "{" {
//                count += 1
//            } else if character == "}" {
//                count -= 1
//            }
//
//            if count == 0 {
//                return string.index(string.startIndex, offsetBy: index + 1)
//            }
//        }
//        return nil
//    }
}
