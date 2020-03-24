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

typealias TranslatorInfo = [String: Any]

protocol TranslatorsControllerCoordinatorDelegate: class {
    func showTranslationError(_ error: Error, result: (Bool) -> Void)
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
        case bundleMissing
        case cantParseIndexFile
        case incompatibleTranslator
    }

    @UserDefault(key: "TranslatorLastCommitHash", defaultValue: nil)
    private var lastCommitHash: String?
    @UserDefault(key: "TranslatorLastTimestamp", defaultValue: 0)
    private var lastTimestamp: Double
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
                return self.updateFromRepo(type: type)
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.isLoading.accept(false)
            }, onError: { [weak self] error in
                self?.coordinatorDelegate?.showTranslationError(error, result: { shouldReset in
                    if shouldReset {
                        self?.resetToBundle()
                    } else {
                        self?.isLoading.accept(false)
                    }
                })
            })
            .disposed(by: self.disposeBag)
    }

    private func updateFromBundle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(Error.expired))
                return Disposables.create()
            }
            guard let hashPath = Bundle.main.path(forResource: "commit_hash", ofType: "txt"),
                  let timestampPath = Bundle.main.path(forResource: "timestamp", ofType: "txt"),
                  let hash = try? String(contentsOf: URL(fileURLWithPath: hashPath)),
                  let timestamp = (try? String(contentsOf: URL(fileURLWithPath: timestampPath))).flatMap(Double.init) else {
                subscriber(.error(Error.bundleMissing))
                return Disposables.create()
            }

            do {
                if self.lastCommitHash != hash {
                    try self.syncTranslatorsWithBundledData()
                    self.lastCommitHash = hash
                    self.lastTimestamp = timestamp
                }
                subscriber(.success(()))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }

    private func syncTranslatorsWithBundledData() throws {
        guard let zipUrl = Bundle.main.path(forResource: "translators", ofType: "zip").flatMap({ URL(fileURLWithPath: $0) }) else {
            throw Error.bundleMissing
        }

        let metadata = try self.loadTranslatorsIndex()
        let (updated, deleted) = try self.dbStorage.createCoordinator().perform(request: SyncTranslatorsDbRequest(metadata: metadata))

        deleted.forEach { filename in
            try? self.fileStorage.remove(Files.translator(filename: filename))
        }

        guard !updated.isEmpty else { return }

        try Zip.unzipFile(zipUrl, destination: Files.tmpTranslators.createUrl(), overwrite: true, password: nil)

        updated.forEach { filename in
            try? self.fileStorage.move(from: Files.tmpTranslator(filename: filename),
                                       to: Files.translator(filename: filename))
        }

        try? self.fileStorage.remove(Files.tmpTranslators)
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

    func updateFromRepo(type: UpdateType) -> Single<()> {
        return Single.just(())
    }

    func resetToBundle() {

    }

    func translators() -> Single<[TranslatorInfo]> {
        if !self.isLoading.value {
            return self.loadTranslators(from: Files.translators)
        }
        return self.isLoading.filter({ !$0 }).first().flatMap { _ in self.loadTranslators(from: Files.translators) }
    }

    private func loadTranslators(from file: File) -> Single<[TranslatorInfo]> {
        do {
            let contents: [File] = try self.fileStorage.contentsOfDirectory(at: file)
            let translators = contents.compactMap({ self.loadTranslatorInfo(from: $0) })
            return Single.just(translators)
        } catch let error {
            DDLogError("TranslatorController: error - \(error)")
            return Single.error(error)
        }
    }

    private func loadTranslatorInfo(from file: File) -> TranslatorInfo? {
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
