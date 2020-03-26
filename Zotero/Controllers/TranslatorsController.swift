//
//  TranslatorsController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxCocoa
import RxSwift
import Zip

typealias RawTranslator = [String: Any]

protocol TranslatorsControllerCoordinatorDelegate: class {
    func showRemoteLoadTranslatorsError(result: (Bool) -> Void)
    func showBundleLoadTranslatorsError(result: (Bool) -> Void)
}

class TranslatorsController {
    enum UpdateType: Int {
        case manual = 1
        case initial = 2
        case startup = 3
        case notification = 4
    }

    enum Error: Swift.Error {
        case expired
        case bundleLoading(Swift.Error)
        case bundleMissing
        case cantParseIndexFile
        case incompatibleTranslator

        var isBundeLoadingError: Bool {
            switch self {
            case .bundleLoading: return true
            default: return false
            }
        }
    }

    @UserDefault(key: "TranslatorLastCommitHash", defaultValue: nil)
    private var lastCommitHash: String?
    @UserDefault(key: "TranslatorLastTimestamp", defaultValue: 0)
    private var lastTimestamp: Double
    @UserDefault(key: "TranslatorLastDeletedVersion", defaultValue: 0)
    private var lastDeleted: Int
    private var lastDate: Date {
        return Date(timeIntervalSince1970: self.lastTimestamp)
    }
    private var isLoading: BehaviorRelay<Bool>

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let dbStorage: DbStorage

    weak var coordinatorDelegate: TranslatorsControllerCoordinatorDelegate?

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        do {
            try fileStorage.createDirectories(for: Files.translatorsDbFile)
        } catch let error {
            fatalError("TranslatorsController: could not create db directories - \(error)")
        }

        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = RealmDbStorage(url: Files.translatorsDbFile.createUrl())
        self.isLoading = BehaviorRelay(value: false)
        self.disposeBag = DisposeBag()
    }

    func update() {
        self.isLoading.accept(true)
        let type: UpdateType = self.lastCommitHash == nil ? .initial : .startup
        self.updateFromBundle()
            .flatMap {
                return self._updateFromRepo(type: type)
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.isLoading.accept(false)
            }, onError: { [weak self] error in
                self?.process(error: error, updateType: type)
            })
            .disposed(by: self.disposeBag)
    }

    private func process(error: Swift.Error, updateType: UpdateType) {
        // In case of bundle loading error ask user whether we should try to reset.

        if (error as? Error)?.isBundeLoadingError == true {
            self.coordinatorDelegate?.showBundleLoadTranslatorsError { [weak self] shouldReset in
                if shouldReset {
                    self?.resetToBundle()
                } else {
                    self?.isLoading.accept(false)
                }
            }
            return
        }

        self.coordinatorDelegate?.showRemoteLoadTranslatorsError { retry in
            if retry {
                self.updateFromRepo(type: updateType)
            } else {
                self.isLoading.accept(false)
            }
        }
    }

    private func updateFromBundle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(Error.bundleLoading(Error.expired)))
                return Disposables.create()
            }
            guard let hashPath = Bundle.main.path(forResource: "commit_hash", ofType: "txt"),
                  let timestampPath = Bundle.main.path(forResource: "timestamp", ofType: "txt"),
                  let deletedUrl = Bundle.main.path(forResource: "deleted", ofType: "txt").flatMap({ URL(fileURLWithPath: $0) }),
                  let (deletedVersion, deletedIndices) = (try? String(contentsOf: deletedUrl)).flatMap({ self.parse(deleted: $0) }),
                  let hash = try? String(contentsOf: URL(fileURLWithPath: hashPath)),
                  let timestamp = (try? String(contentsOf: URL(fileURLWithPath: timestampPath))).flatMap(Double.init) else {
                subscriber(.error(Error.bundleLoading(Error.bundleMissing)))
                return Disposables.create()
            }

            do {
                if self.lastCommitHash != hash {
                    try self.syncTranslatorsWithBundledData(deletedIndices: deletedIndices)
                    self.lastCommitHash = hash
                    self.lastTimestamp = timestamp
                    self.lastDeleted = deletedVersion
                }
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(Error.bundleLoading(error)))
            }

            return Disposables.create()
        }
    }

    private func syncTranslatorsWithBundledData(deletedIndices: [String]) throws {
        guard let zipUrl = Bundle.main.path(forResource: "translators", ofType: "zip").flatMap({ URL(fileURLWithPath: $0) }) else {
            throw Error.bundleMissing
        }

        let metadata = try self.loadTranslatorsIndex()
        let request = SyncTranslatorsDbRequest(updateMetadata: metadata, deleteIndices: deletedIndices)
        let (update, delete) = try self.dbStorage.createCoordinator().perform(request: request)

        delete.forEach { filename in
            try? self.fileStorage.remove(Files.translator(filename: filename))
        }

        guard !update.isEmpty else { return }

        try Zip.unzipFile(zipUrl, destination: Files.tmpTranslators.createUrl(), overwrite: true, password: nil)

        update.forEach { filename in
            try? self.fileStorage.move(from: Files.tmpTranslator(filename: filename),
                                       to: Files.translator(filename: filename))
        }

        try? self.fileStorage.remove(Files.tmpTranslators)
    }

    private func parse(deleted: String) -> (Int, [String])? {
        let deletedLines = deleted.split(whereSeparator: { $0.isNewline })
        // TODO: - finish
        return nil
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

    func updateFromRepo(type: UpdateType) {
        self.isLoading.accept(true)
        self._updateFromRepo(type: type)
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.isLoading.accept(false)
            }, onError: { [weak self] error in
                self?.process(error: error, updateType: type)
            })
            .disposed(by: self.disposeBag)
    }

    private func _updateFromRepo(type: UpdateType) -> Single<Int> {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let request = TranslatorsRequest(timestamp: Int(self.lastTimestamp), version: "\(version)-iOS", type: type.rawValue)
        return self.apiClient.send(request: request)
                             .flatMap { data, _ -> Single<([Translator], Int)> in
                                 let delegate = TranslatorParserDelegate()
                                 let parser = XMLParser(data: data)
                                 parser.delegate = delegate
                                 if parser.parse() {
                                     return Single.just((delegate.translators, delegate.timestamp))
                                 } else {
                                     return Single.just(([], Int(Date().timeIntervalSince1970)))
                                 }
                             }
                             .flatMap { translators, timestamp in
                                return self.update(translators: translators).flatMap({ return Single.just(timestamp) })
                             }
    }

    private func update(translators: [Translator]) -> Single<()> {
        do {
            let (updateTranslators, deleteTranslators) = self.split(translators: translators)
            let updateMetadata = updateTranslators.compactMap({ self.metadata(from: $0) })
            let deleteMetadata = deleteTranslators.compactMap({ self.metadata(from: $0) })

            // Sanity check, if some translators can't be mapped to metadata they are missing important information.
            if updateMetadata.count != updateTranslators.count || deleteMetadata.count != deleteTranslators.count {
                return Single.error(Error.incompatibleTranslator)
            }

            let request = SyncTranslatorsDbRequest(updateMetadata: updateMetadata, deleteIndices: deleteMetadata.map({ $0.id }))
            _ = try self.dbStorage.createCoordinator().perform(request: request)

            for metadata in deleteMetadata {
                try? self.fileStorage.remove(Files.translator(filename: metadata.filename))
            }
            for (index, metadata) in updateMetadata.enumerated() {
                guard let data = self.data(from: updateTranslators[index]) else {
                    return Single.error(Error.incompatibleTranslator)
                }
                try? self.fileStorage.write(data, to: Files.translator(filename: metadata.filename), options: .atomicWrite)
            }

            return Single.just(())
        } catch let error {
            return Single.error(error)
        }
    }

    private func split(translators: [Translator]) -> (update: [Translator], delete: [Translator]) {
        var update: [Translator] = []
        var delete: [Translator] = []

        for translator in translators {
            guard let priority = translator.metadata["priority"].flatMap(Int.init) else { continue }
            if priority > 0 {
                update.append(translator)
            } else {
                delete.append(translator)
            }
        }

        return (update, delete)
    }

    private func metadata(from translator: Translator) -> TranslatorMetadata? {
        guard let id = translator.metadata["id"],
              let label = translator.metadata["label"] else { return nil }
        var metadata = translator.metadata
        metadata["fileName"] = label + ".js"
        return TranslatorMetadata(id: id, data: metadata)
    }

    private func data(from translator: Translator) -> Data? {
        guard let jsonMetadata = try? JSONSerialization.data(withJSONObject: translator.metadata, options: .prettyPrinted),
              let code = translator.code.data(using: .utf8),
              let newlines = "\n\n".data(using: .utf8) else { return nil }
        var data = jsonMetadata
        data.append(newlines)
        data.append(code)
        return data
    }

    func resetToBundle() {
//        XMLParser
    }

    func translators() -> Single<[RawTranslator]> {
        if !self.isLoading.value {
            return self.loadTranslators(from: Files.translators)
        }
        return self.isLoading.filter({ !$0 }).first().flatMap { _ in self.loadTranslators(from: Files.translators) }
    }

    private func loadTranslators(from file: File) -> Single<[RawTranslator]> {
        do {
            let contents: [File] = try self.fileStorage.contentsOfDirectory(at: file)
            let translators = contents.compactMap({ self.loadTranslatorInfo(from: $0) })
            return Single.just(translators)
        } catch let error {
            DDLogError("TranslatorController: error - \(error)")
            return Single.error(error)
        }
    }

    private func loadTranslatorInfo(from file: File) -> RawTranslator? {
        guard file.ext == "js" else { return nil }

        do {
            let data = try self.fileStorage.read(file)

            guard let string = String(data: data, encoding: .utf8),
                  let endingIndex = self.metadataIndex(from: string),
                  let metadataData = string[string.startIndex..<endingIndex].data(using: .utf8),
                  var metadata = try JSONSerialization.jsonObject(with: metadataData, options: .allowFragments) as? [String: Any] else {
                throw Error.incompatibleTranslator
            }

            metadata["code"] = string

            return metadata
        } catch let error {
            DDLogError("TranslatorsController: cant' read data from \(file.createUrl()) - \(error)")
            return nil
        }
    }

    private func metadataIndex(from string: String) -> String.Index? {
        var count = 0
        for (index, character) in string.enumerated() {
            if character == "{" {
                count += 1
            } else if character == "}" {
                count -= 1
            }

            if count == 0 {
                return string.index(string.startIndex, offsetBy: index + 1)
            }
        }
        return nil
    }
}
