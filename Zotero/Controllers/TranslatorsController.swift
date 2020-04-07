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
import ZIPFoundation

typealias RawTranslator = [String: Any]

protocol TranslatorsControllerCoordinatorDelegate: class {
    func showRemoteLoadTranslatorsError(result: @escaping (Bool) -> Void)
    func showBundleLoadTranslatorsError(result: @escaping (Bool) -> Void)
    func showResetToBundleError()
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
        case incompatibleDeleted
        case cantParseXmlResponse

        var isBundeLoadingError: Bool {
            switch self {
            case .bundleLoading: return true
            default: return false
            }
        }
    }

    @UserDefault(key: "TranslatorLastCommitHash", defaultValue: "")
    private var lastCommitHash: String
    @UserDefault(key: "TranslatorLastTimestamp", defaultValue: 0)
    private var lastTimestamp: Double
    @UserDefault(key: "TranslatorLastDeletedVersion", defaultValue: 0)
    private var lastDeleted: Int
    private(set) var isLoading: BehaviorRelay<Bool>
    var lastUpdate: Date {
        return Date(timeIntervalSince1970: self.lastTimestamp)
    }

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let dbStorage: DbStorage
    private let bundle: Bundle

    weak var coordinator: TranslatorsControllerCoordinatorDelegate?

    init(apiClient: ApiClient, indexStorage: DbStorage, fileStorage: FileStorage, bundle: Bundle = Bundle.main) {
        do {
            try fileStorage.createDirectories(for: Files.translatorsDbFile)
        } catch let error {
            fatalError("TranslatorsController: could not create db directories - \(error)")
        }

        self.bundle = bundle
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = indexStorage
        self.isLoading = BehaviorRelay(value: false)
        self.disposeBag = DisposeBag()
    }

    // MARK: - Actions

    /// Loads bundled translators if needed, then loads remote translators.
    func update() {
        self.isLoading.accept(true)
        let type: UpdateType = self.lastCommitHash == "" ? .initial : .startup
        self.updateFromBundle()
            .flatMap {
                return self._updateFromRepo(type: type)
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] timestamp in
                self?.lastTimestamp = timestamp
                self?.isLoading.accept(false)
            }, onError: { [weak self] error in
                self?.process(error: error)
            })
            .disposed(by: self.disposeBag)
    }

    /// Update local translators with bundled translators if needed.
    private func updateFromBundle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(Error.bundleLoading(Error.expired)))
                return Disposables.create()
            }

            do {
                let hash = try self.loadLastCommitHash()

                if self.lastCommitHash != hash {
                    let timestamp = try self.loadLastTimestamp()
                    let (deletedVersion, deletedIndices) = try self.loadDeleted()

                    try self.syncTranslatorsWithBundledData(deleteIndices: deletedIndices)
                    
                    self.lastCommitHash = hash
                    if timestamp > self.lastTimestamp {
                        self.lastTimestamp = timestamp
                    }
                    self.lastDeleted = deletedVersion
                }

                subscriber(.success(()))
            } catch let error {
                subscriber(.error(Error.bundleLoading(error)))
            }

            return Disposables.create()
        }
    }

    /// Manual update of translators from remote repo.
    func updateFromRepo() {
        self.isLoading.accept(true)
        self._updateFromRepo(type: .manual)
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] timestamp in
                self?.lastTimestamp = timestamp
                self?.isLoading.accept(false)
            }, onError: { [weak self] error in
                self?.process(error: error)
            })
            .disposed(by: self.disposeBag)
    }

    /// Loads remote translators and syncs them with local data.
    /// - parameter type: Type of repo update.
    /// - returns: Timestamp of repo update.
    private func _updateFromRepo(type: UpdateType) -> Single<Double> {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let request = TranslatorsRequest(timestamp: self.lastTimestamp, version: "\(version)-iOS", type: type.rawValue)
        return self.apiClient.send(request: request)
                             .flatMap { data, _ -> Single<(Double, [Translator])> in
                                do {
                                    let response = try self.parseXmlTranslators(from: data)
                                    return Single.just(response)
                                } catch let error {
                                    return Single.error(error)
                                }
                             }
                             .flatMap { timestamp, translators in
                                return self.syncTranslatorsWithRemote(translators: translators).flatMap({ return Single.just(timestamp) })
                             }
    }

    /// Checks whether the error was caused by bundled or remote loading and shows appropriate error.
    /// - parameter error: Error to check.
    private func process(error: Swift.Error) {
        guard let delegate = self.coordinator else {
            self.isLoading.accept(false)
            return
        }

        // In case of bundle loading error ask user whether we should try to reset.
        if (error as? Error)?.isBundeLoadingError == true {
            delegate.showBundleLoadTranslatorsError { [weak self] shouldReset in
                if shouldReset {
                    self?.resetToBundle()
                } else {
                    self?.isLoading.accept(false)
                }
            }
            return
        }

        delegate.showRemoteLoadTranslatorsError { retry in
            if retry {
                self.updateFromRepo()
            } else {
                self.isLoading.accept(false)
            }
        }
    }

    /// Sync local translators with bundled translators.
    private func syncTranslatorsWithBundledData(deleteIndices: [String]) throws {
        let metadata = try self.loadIndex()
        let request = SyncTranslatorsDbRequest(updateMetadata: metadata, deleteIndices: deleteIndices)
        let updated = try self.dbStorage.createCoordinator().perform(request: request)

        deleteIndices.forEach { id in
            try? self.fileStorage.remove(Files.translator(filename: id))
        }

        try self.unzip(translators: updated)
    }

    /// Unzip individual translators from bundled zip file to translator location.
    /// - parameter translators: Array of tuples. Each tuple consists of translator id and translator filename.
    private func unzip(translators: [(id: String, filename: String)]) throws {
        guard let zipUrl = self.bundle.path(forResource: "bundled/translators/translators", ofType: "zip").flatMap({ URL(fileURLWithPath: $0) }),
              let archive = Archive(url: zipUrl, accessMode: .read) else {
            throw Error.bundleMissing
        }
        for (id, filename) in translators {
            guard let entry = archive[filename] else { continue }
            let file = Files.translator(filename: id)
            try? self.fileStorage.remove(file)
            _ = try archive.extract(entry, to: file.createUrl())
        }
    }

    /// Sync local translators with remote translators.
    /// - parameter translators: Translators to be updated or removed.
    private func syncTranslatorsWithRemote(translators: [Translator]) -> Single<()> {
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
                try? self.fileStorage.remove(Files.translator(filename: metadata.id))
            }
            for (index, metadata) in updateMetadata.enumerated() {
                guard let data = self.data(from: updateTranslators[index]) else {
                    return Single.error(Error.incompatibleTranslator)
                }
                try? self.fileStorage.write(data, to: Files.translator(filename: metadata.id), options: .atomicWrite)
            }

            return Single.just(())
        } catch let error {
            return Single.error(error)
        }
    }

    /// Manual reset of translators.
    func resetToBundle() {
        do {
            try self._resetToBundle()
        } catch let error {
            DDLogError("TranslatorsController: can't reset to bundle - \(error)")
            self.coordinator?.showResetToBundleError()
        }
    }

    /// Reset local translators to match bundled translators.
    private func _resetToBundle() throws {
        guard let zipUrl = self.bundle.path(forResource: "bundled/translators/translators", ofType: "zip")
                                      .flatMap({ URL(fileURLWithPath: $0) }),
              let archive = Archive(url: zipUrl, accessMode: .read) else {
            throw Error.bundleMissing
        }

        let timestamp = try self.loadLastTimestamp()
        let metadata = try self.loadIndex()

        try? self.fileStorage.remove(Files.translators)
        try self.fileStorage.createDirectories(for: Files.translators)
        for data in metadata {
            guard let entry = archive[data.filename] else { continue }
            _ = try archive.extract(entry, to: Files.translator(filename: data.id).createUrl())
        }

        try self.dbStorage.createCoordinator().perform(request: ResetTranslatorsDbRequest(metadata: metadata))
        self.lastTimestamp = timestamp
    }

    // MARK: - Translator loading

    /// Loads raw translators if they are not currently being loaded. Otherwise waits for loading and returns them afterwards.
    /// - returns: Raw translators.
    func translators() -> Single<[RawTranslator]> {
        if !self.isLoading.value {
            return self.loadTranslators()
        }
        return self.isLoading.filter({ !$0 }).first().flatMap { _ in self.loadTranslators() }
    }

    /// Load local raw translators for javascript.
    /// - returns: Raw translators.
    private func loadTranslators() -> Single<[RawTranslator]> {
        do {
            let contents: [File] = try self.fileStorage.contentsOfDirectory(at: Files.translators)
            let translators = contents.compactMap({ self.loadRawTranslator(from: $0) })
            return Single.just(translators)
        } catch let error {
            DDLogError("TranslatorController: error - \(error)")
            return Single.error(error)
        }
    }

    /// Loads raw translator dictionary from translator file.
    /// - parameter file: File of translator.
    /// - returns: Raw translator data.
    private func loadRawTranslator(from file: File) -> RawTranslator? {
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

    /// Finds `endIndex` of metadata part in translator file (translator file consists of json metadata and code).
    /// - parameter string: Raw translator file string.
    /// - returns: End index of json metadata.
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

    // MARK: - Helpers

    /// Parses version and indices from `deleted.txt` file and
    /// checks whether deleted version is higher than `lastDeletedVersion`. Returns data accordingly.
    /// - parameter deleted: Raw `deleted.txt` string.
    /// - parameter lastDeletedVersion: Version of `deleted.txt` file which was processed last.
    /// - returns: If `version > lastDeletedVersion` return tuple with `version` and parsed indices.
    ///            Otherwise return tuple with `lastDeletedVersion` and empty array.
    private func parse(deleted: String, lastDeletedVersion: Int) -> (Int, [String])? {
        let deletedLines = deleted.split(whereSeparator: { $0.isNewline })
        guard !deletedLines.isEmpty,
              let version = self.parseDeleted(line: deletedLines[0]).flatMap(Int.init) else { return nil }

        if version <= lastDeletedVersion {
            return (lastDeletedVersion, [])
        }

        let indices = (1..<deletedLines.count).compactMap({ self.parseDeleted(line: deletedLines[$0]) })
        return (version, indices)
    }

    /// Parses value from a line from `deleted.txt` file. Each line contains a value followed by a comment.
    /// - parameter line: Line to be parsed.
    /// - returns: Parsed value if comment was found. `nil` otherwise.
    private func parseDeleted(line: String.SubSequence) -> String? {
        guard let index = line.firstIndex(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return String(line[line.startIndex..<index])
    }

    /// Splits translators returned by repo, which contain both translators to be updated and deleted.
    /// Translators which need to be deleted have `priority = 0`, other translators have `priority > 0`.
    /// - parameter translators: Translators returned by repo.
    /// - returns: Translators split into those which need to be updated and those which need to be deleted.
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

    /// Parses metadata from `Translator` and converts them to `TranslatorMetadata`.
    /// - parameter translator: Translator to be converted.
    /// - returns: Metadata of given translator.
    private func metadata(from translator: Translator) -> TranslatorMetadata? {
        guard let id = translator.metadata["id"],
              let rawLastUpdated = translator.metadata["lastUpdated"] else { return nil }
        return try? TranslatorMetadata(id: id, filename: "", rawLastUpdated: rawLastUpdated)
    }

    /// Converts `Translator` to `Data` which can be written to file.
    /// - parameter translator: Translator to be converted.
    /// - returns: Converted data.
    private func data(from translator: Translator) -> Data? {
        guard let jsonMetadata = try? JSONSerialization.data(withJSONObject: translator.metadata, options: .prettyPrinted),
              let code = translator.code.data(using: .utf8),
              let newlines = "\n\n".data(using: .utf8) else { return nil }
        var data = jsonMetadata
        data.append(newlines)
        data.append(code)
        return data
    }

    /// Parse XML response from translator repo.
    /// - parameter data: Data to be parsed.
    /// - returns: Tupe, where first value is the "currentTime" and second value is an array of parsed `Translator`s.
    private func parseXmlTranslators(from data: Data) throws -> (Double, [Translator]) {
        let delegate = TranslatorParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        if parser.parse() {
            return (delegate.timestamp, delegate.translators)
        }

        throw Error.cantParseXmlResponse
    }

    // MARK: - Bundle loading

    /// Load bundled index file and parse translator metadata.
    /// - returns: Parsed translator metadata.
    private func loadIndex() throws -> [TranslatorMetadata] {
        guard let indexFilePath = self.bundle.path(forResource: "bundled/translators/index", ofType: "json") else {
            throw Error.bundleMissing
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: indexFilePath))
        let decoded = try JSONDecoder().decode(TranslatorMetadatas.self, from: data)
        return decoded.metadatas
    }

    /// Load bundled deleted.txt file and parse version and indices stored there.
    /// - returns: Tuple, where first value is the version of deleted file and second value is an array of indices of translators to be deleted.
    private func loadDeleted() throws -> (Int, [String]) {
        return try self.loadFromBundle(resource: "bundled/translators/deleted", type: "txt", map: {
            guard let data = self.parse(deleted: $0, lastDeletedVersion: self.lastDeleted) else {
                throw Error.incompatibleDeleted
            }
            return data
        })
    }

    /// Load bundled last timestamp.
    /// - returns: Last timestamp.
    private func loadLastTimestamp() throws -> Double {
        return try self.loadFromBundle(resource: "bundled/translators/timestamp", type: "txt", map: {
            guard let value = Double($0) else { throw Error.bundleMissing }
            return value
        })
    }

    /// Load bundled last commit hash.
    /// - returns: Commit hash.
    private func loadLastCommitHash() throws -> String {
        return try self.loadFromBundle(resource: "bundled/translators/commit_hash", type: "txt", map: { return $0 })
    }

    /// Load bundled data and map it to appropriate type.
    /// - parameter resource: Resource name to load.
    /// - parameter type: File extension of resource to load.
    /// - parameter map: Mapping function to convert the raw string to appropriate value.
    /// - returns: Returns mapped result.
    private func loadFromBundle<Result>(resource: String, type: String, map: (String) throws -> Result) throws -> Result {
        guard let url = self.bundle.path(forResource: resource, ofType: type).flatMap({ URL(fileURLWithPath: $0) }),
              let rawValue = try? String(contentsOf: url) else {
            throw Error.bundleMissing
        }
        return try map(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Testing

    func setupTest(timestamp: Double, hash: String, deleted: Int) {
        self.lastTimestamp = timestamp
        self.lastCommitHash = hash
        self.lastDeleted = deleted
    }
}
