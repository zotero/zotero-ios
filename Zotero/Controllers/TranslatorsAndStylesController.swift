//
//  TranslatorsAndStylesController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxCocoa
import RxSwift
import ZIPFoundation

typealias RawTranslator = [String: Any]

protocol TranslatorsControllerCoordinatorDelegate: AnyObject {
    func showBundleLoadTranslatorsError(result: @escaping (Bool) -> Void)
    func showResetToBundleError()
}

final class TranslatorsAndStylesController {
    enum UpdateType: Int {
        case manual = 1
        case initial = 2
        case startup = 3
        case notification = 4
        case shareExtension = 5
    }

    enum Error: Swift.Error {
        case expired
        case bundleLoading(Swift.Error)
        case bundleMissing
        case incompatibleDeleted
        case cantParseXmlResponse
        case cantConvertTranslatorToData
        case translatorMissingId
        case translatorMissingLastUpdated

        var isBundeLoadingError: Bool {
            switch self {
            case .bundleLoading: return true
            default: return false
            }
        }
    }

    @UserDefault(key: "TranslatorLastTimestamp", defaultValue: 0)
    private var lastTimestamp: Int
    @UserDefault(key: "TranslatorLastCommitHash", defaultValue: "")
    private var lastTranslatorCommitHash: String
    @UserDefault(key: "TranslatorLastDeletedVersion", defaultValue: 0)
    private var lastTranslatorDeleted: Int
    @UserDefault(key: "StylesLastCommitHash", defaultValue: "")
    private var lastStylesCommitHash: String
    @UserDefault(key: "TranslatorsDidResetToBundleFix", defaultValue: false)
    private var translatorsDidReset: Bool
    private(set) var isLoading: BehaviorRelay<Bool>
    var lastUpdate: Date {
        return Date(timeIntervalSince1970: Double(self.lastTimestamp))
    }

    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag
    private let bundle: Bundle
    private let queue: DispatchQueue
    private let scheduler: SchedulerType

    weak var coordinator: TranslatorsControllerCoordinatorDelegate?
    private lazy var uuidExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}"#)
        } catch let error {
            DDLogError("TranslatorsAndStylesController: can't create uuid expression - \(error)")
            return nil
        }
    }()

    init(apiClient: ApiClient, bundledDataStorage: DbStorage, fileStorage: FileStorage, bundle: Bundle = Bundle.main) {
        do {
            try fileStorage.createDirectories(for: Files.bundledDataDbFile)
        } catch let error {
            fatalError("TranslatorsAndStylesController: could not create db directories - \(error)")
        }

        let queue = DispatchQueue(label: "org.zotero.TranslatorsController.queue", qos: .utility, attributes: .concurrent)

        self.bundle = bundle
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = bundledDataStorage
        self.isLoading = BehaviorRelay(value: false)
        self.disposeBag = DisposeBag()
        self.queue = queue
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
    }

    // MARK: - Actions

    /// Loads bundled translators if needed, then loads remote translators.
    func update() {
        let type: UpdateType = self.lastTranslatorCommitHash == "" ? .initial : .startup

        self.isLoading.accept(true)

        DDLogInfo("TranslatorsAndStylesController: update translators and styles")

        self.updateFromBundle()
            .subscribe(on: self.scheduler)
            .flatMap {
                return self._updateFromRepo(type: type)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] timestamp in
                self?.lastTimestamp = timestamp
                self?.isLoading.accept(false)
            }, onFailure: { [weak self] error in
                self?.process(error: error, updateType: type)
            })
            .disposed(by: self.disposeBag)
    }

    /// Update local assets with bundled assets if needed.
    private func updateFromBundle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.failure(Error.bundleLoading(Error.expired)))
                return Disposables.create()
            }

            do {
                try self._updateTranslatorsFromBundle()
                try self._updateStylesFromBundle()

                let timestamp = try self.loadLastTimestamp()
                if timestamp > self.lastTimestamp {
                    self.lastTimestamp = timestamp
                }

                subscriber(.success(()))
            } catch let error {
                DDLogError("TranslatorsAndStylesController: can't update from bundle - \(error)")
                subscriber(.failure(Error.bundleLoading(error)))
            }

            return Disposables.create()
        }
    }

    /// Update local translators with bundled translators if needed.
    private func _updateTranslatorsFromBundle() throws {
        // A fix for issue in Beta. Translators from repo API were stored with incorrect id key ("id" instead of "translatorID"). Force reset to bundled translators once to fix the stored id key.
        // TODO: - this can be removed later
        if !self.translatorsDidReset {
            try self._resetToBundle()
            self.translatorsDidReset = true
        }

        let hash = try self.loadLastTranslatorCommitHash()

        guard self.lastTranslatorCommitHash != hash else { return }

        DDLogInfo("TranslatorsAndStylesController: update translators from bundle")

        let (deletedVersion, deletedIndices) = try self.loadDeleted()
        try self.syncTranslatorsWithBundledData(deleteIndices: deletedIndices)

        self.lastTranslatorDeleted = deletedVersion
        self.lastTranslatorCommitHash = hash
    }

    /// Update local styles with bundled styles if needed.
    private func _updateStylesFromBundle() throws {
        let hash = try self.loadLastStylesCommitHash()

        guard self.lastStylesCommitHash != hash else { return }

        DDLogInfo("TranslatorsAndStylesController: update styles from bundle")

        try self.syncStylesWithBundledData()

        self.lastStylesCommitHash = hash
    }

    /// Manual update of translators from remote repo.
    func updateFromRepo(type: UpdateType) {
        self.isLoading.accept(true)
        self._updateFromRepo(type: type)
            .subscribe(on: self.scheduler)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] timestamp in
                self?.lastTimestamp = timestamp
                self?.isLoading.accept(false)
            }, onFailure: { [weak self] error in
                self?.process(error: error, updateType: type)
            })
            .disposed(by: self.disposeBag)
    }

    /// Loads remote translators and syncs them with local data.
    /// - parameter type: Type of repo update.
    /// - returns: Timestamp of repo update.
    private func _updateFromRepo(type: UpdateType) -> Single<Int> {
        // Startup update is limited to once daily, other updates happen always
        guard type != .startup || self.didDayChange(from: Date(timeIntervalSince1970: Double(self.lastTimestamp))) else { return Single.just(self.lastTimestamp) }

        DDLogInfo("TranslatorsAndStylesController: update from repo")

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let bundle = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        let request = RepoRequest(timestamp: self.lastTimestamp, version: "\(version)-\(bundle)-iOS", type: type.rawValue, styles: self.styles(for: type))
        return self.apiClient.send(request: request, queue: self.queue)
                             .observe(on: self.scheduler)
                             .flatMap { data, _ -> Single<(Int, [Translator], [(String, String)])> in
                                 do {
                                     let response = try self.parseRepoResponse(from: data)
                                     return Single.just(response)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
                             .flatMap { timestamp, translators, styles in
                                 return self.syncRepoResponse(translators: translators, styles: styles).flatMap({ return Single.just(timestamp) })
                             }
    }

    private func styles(for type: UpdateType) -> [Style]? {
        guard type != .shareExtension else { return nil }

        do {
            return try self.dbStorage.createCoordinator().perform(request: ReadStylesDbRequest()).compactMap(Style.init)
        } catch let error {
            DDLogError("TranslatorsAndStylesController: can't read styles - \(error)")
            return nil
        }
    }

    private func didDayChange(from date: Date) -> Bool {
        let calendar = Calendar.current

        let dateComponents = calendar.dateComponents([.day, .month, .year], from: date)
        let todayComponents = calendar.dateComponents([.day, .month, .year], from: Date())

        return dateComponents.day != todayComponents.day || dateComponents.month != todayComponents.month || dateComponents.year != todayComponents.year
    }

    /// Checks whether the error was caused by bundled or remote loading and shows appropriate error.
    /// - parameter error: Error to check.
    private func process(error: Swift.Error, updateType: UpdateType) {
        DDLogError("TranslatorsAndStylesController: error - \(error)")

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
        }
    }

    /// Sync local translators with bundled translators.
    private func syncTranslatorsWithBundledData(deleteIndices: [String]) throws {
        // Load metadata index
        let metadata = try self.loadIndex()
        // Sync translators
        let request = SyncTranslatorsDbRequest(updateMetadata: metadata, deleteIndices: deleteIndices, fileStorage: self.fileStorage)
        let updated = try self.dbStorage.createCoordinator().perform(request: request)
        DDLogInfo("TranslatorsAndStylesController: updated \(updated.count) translators")
        // Delete files of deleted translators
        deleteIndices.forEach { id in
            try? self.fileStorage.remove(Files.translator(filename: id))
        }
        // Unzip updated translators
        try self.unzip(translators: updated)
        DDLogInfo("TranslatorsAndStylesController: unzipped translators")
    }

    /// Sync local styles with bundled styles.
    private func syncStylesWithBundledData() throws {
        guard let stylesUrl = self.bundle.path(forResource: "Bundled/styles", ofType: "").flatMap({ URL(fileURLWithPath: $0) }) else {
            throw Error.bundleMissing
        }

        // Load file metadata of bundled styles
        let files: [File] = try self.fileStorage.contentsOfDirectory(at: Files.file(from: stylesUrl))
        let styles: [Style] = files.compactMap({ file in
            guard file.ext == "csl" else { return nil }
            return try? self.parseStyle(from: file)
        })
        // Sync styles
        let request = SyncStylesDbRequest(styles: styles)
        let updated = try self.dbStorage.createCoordinator().perform(request: request)
        DDLogInfo("TranslatorsAndStylesController: updated \(updated.count) styles")
        // Copy updated files
        for file in files.filter({ updated.contains($0.name) }) {
            try self.fileStorage.copy(from: file, to: Files.style(filename: file.name))
        }
    }

    /// Unzip individual translators from bundled zip file to translator location.
    /// - parameter translators: Array of tuples. Each tuple consists of translator id and translator filename.
    private func unzip(translators: [(id: String, filename: String)]) throws {
        guard let zipUrl = self.bundle.path(forResource: "Bundled/translators/translators", ofType: "zip").flatMap({ URL(fileURLWithPath: $0) }),
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
    private func syncRepoResponse(translators: [Translator], styles: [(String, String)]) -> Single<()> {
        return Single.create { subscriber in
            do {
                DDLogInfo("TranslatorsAndStylesController: sync repo response")

                // Split translators into deletions and updates, parse metadata.
                let (updateTranslators, deleteTranslators) = self.split(translators: translators)
                let updateTranslatorMetadata = try updateTranslators.compactMap({ try self.metadata(from: $0) })
                let deleteTranslatorMetadata = try deleteTranslators.compactMap({ try self.metadata(from: $0) })

                // Split styles into metadata and xml data.
                let (updateStyles, stylesData) = self.split(styles: styles)

                DDLogInfo("TranslatorsAndStylesController: update local files from repo")

                // Remove local translators
                for metadata in deleteTranslatorMetadata {
                    try? self.fileStorage.remove(Files.translator(filename: metadata.id))
                }
                // Write updated translators
                for (index, metadata) in updateTranslatorMetadata.enumerated() {
                    let data = try self.data(from: updateTranslators[index])
                    try self.fileStorage.write(data, to: Files.translator(filename: metadata.id), options: .atomicWrite)
                }
                // Write updated styles
                for (filename, data) in stylesData {
                    try self.fileStorage.write(data, to: Files.style(filename: filename), options: .atomicWrite)
                }

                DDLogInfo("TranslatorsAndStylesController: update db from repo")

                // Sync metadata to DB
                let repoRequest = SyncRepoResponseDbRequest(styles: updateStyles, translators: updateTranslatorMetadata, deleteTranslators: deleteTranslatorMetadata, fileStorage: self.fileStorage)
                try self.dbStorage.createCoordinator().perform(request: repoRequest)

                subscriber(.success(()))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    /// Manual reset of translators.
    func resetToBundle(completion: (() -> Void)? = nil) {
        self.queue.async { [weak self] in
            guard let `self` = self else { return }

            do {
                // TODO: - implement styles reset if needed
                try self._resetToBundle()
                self.lastTimestamp = try self.loadLastTimestamp()
                self.lastTranslatorCommitHash = try self.loadLastTranslatorCommitHash()
                self.lastTranslatorDeleted = try self.loadDeleted().0
            } catch let error {
                DDLogError("TranslatorsAndStylesController: can't reset to bundle - \(error)")
                DispatchQueue.main.async {
                    self.coordinator?.showResetToBundleError()
                }
            }

            completion?()
        }
    }

    /// Reset local translators to match bundled translators.
    private func _resetToBundle() throws {
        // Load bundled data
        guard let zipUrl = self.bundle.path(forResource: "Bundled/translators/translators", ofType: "zip")
                                      .flatMap({ URL(fileURLWithPath: $0) }),
              let archive = Archive(url: zipUrl, accessMode: .read) else {
            throw Error.bundleMissing
        }
        let metadata = try self.loadIndex()
        // Remove existing translators and unzip all translators to folder
        if self.fileStorage.has(Files.translators) {
            try self.fileStorage.remove(Files.translators)
        }
        try self.fileStorage.createDirectories(for: Files.translators)
        for data in metadata {
            guard let entry = archive[data.filename] else { continue }
            _ = try archive.extract(entry, to: Files.translator(filename: data.id).createUrl())
        }
        // Reset metadata in database
        try self.dbStorage.createCoordinator().perform(request: ResetTranslatorsDbRequest(metadata: metadata))
    }

    // MARK: - Translator loading

    func translators(matching url: String) -> Single<[RawTranslator]> {
        if !self.isLoading.value {
            return self.loadTranslators(matching: url)
        }

        DDLogInfo("TranslatorsAndStylesController: wait for translators")
        return self.isLoading.filter({ !$0 }).first().flatMap { _ in return self.loadTranslators(matching: url) }
    }

    private func loadTranslators(matching url: String) -> Single<[RawTranslator]> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("TranslatorsAndStylesController: load translators")

            do {
                DDLogInfo("TranslatorsAndStylesController: load raw translators for \(url)")

                var loadedUuids: Set<String> = []
                let allUuids = try self.fileStorage.contentsOfDirectory(at: Files.translators).compactMap({ $0.relativeComponents.last })
                let translators = self.loadTranslatorsWithDependencies(for: Set(allUuids), matching: url, loadedUuids: &loadedUuids)

                DDLogInfo("TranslatorsAndStylesController: found \(translators.count) translators")

                subscriber(.success(translators))
            } catch let error {
                DDLogError("TranslatorsAndStylesController: can't load translators - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func loadTranslatorsWithDependencies(for uuids: Set<String>, matching url: String?, loadedUuids: inout Set<String>) -> [RawTranslator] {
        guard !uuids.isEmpty else { return [] }

        var translators: [RawTranslator] = []
        var dependencies: Set<String> = []

        for uuid in uuids {
            guard !loadedUuids.contains(uuid) else { continue }

            guard let translator = self.loadRawTranslator(from: Files.translator(filename: uuid), ifTargetMatches: url), let id = translator["translatorID"] as? String else { continue }
            loadedUuids.insert(id)
            translators.append(translator)
            // Add dependencies which are not yet loaded
            let deps = self.findDependencies(for: translator).subtracting(loadedUuids).subtracting(loadedUuids)
            dependencies.formUnion(deps)
        }

        // Dependencies don't need to match the URL anymore.
        translators.append(contentsOf: self.loadTranslatorsWithDependencies(for: dependencies, matching: nil, loadedUuids: &loadedUuids))

        return translators
    }

    /// Loads raw translator dictionary from translator file.
    /// - parameter file: File of translator.
    /// - returns: Raw translator data.
    private func loadRawTranslator(from file: File, ifTargetMatches url: String? = nil) -> RawTranslator? {
        let data: Data

        do {
            data = try self.fileStorage.read(file)
        } catch let error {
            DDLogError("TranslatorsAndStylesController: can't read data from \(file.createUrl()) - \(error)")
            return nil
        }

        guard let rawString = String(data: data, encoding: .utf8) else {
            DDLogError("TranslatorsAndStylesController: can't create string from data")
            return nil
        }

        guard let metadataEndIndex = self.metadataIndex(from: rawString),
              let metadataData = rawString[rawString.startIndex..<metadataEndIndex].data(using: .utf8) else {
            DDLogError("TranslatorsAndStylesController: can't find metadata in translator file")
            return nil
        }

        var metadata: [String: Any]
        do {
            let _metadata = try JSONSerialization.jsonObject(with: metadataData, options: .allowFragments)
            guard let _metadata = _metadata as? [String: Any] else {
                DDLogError("TranslatorsAndStylesController: metadata can't be converted to dictionary")
                return nil
            }
            metadata = _metadata
        } catch let error {
            DDLogError("TranslatorsAndStylesController: can't parse metadata - \(error)")
            return nil
        }

        guard let target = metadata["target"] as? String else {
            DDLogError("TranslatorsAndStylesController: \((metadata["label"] as? String) ?? "unknown") raw translator missing target")
            return nil
        }

        if let url = url, !target.isEmpty {
            do {
                let regularExpression = try NSRegularExpression(pattern: target)
                if regularExpression.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) == nil {
                    // Target didn't match url
                    return nil
                }
                DDLogInfo("TranslatorsAndStylesController: \((metadata["label"] as? String) ?? "unknown") matches url")
            } catch let error {
                DDLogError("TranslatorsAndStylesController: can't create regular expression '\(target)' - \(error)")
                return nil
            }
        }

        metadata["code"] = rawString
        // Remap type to translatorType. Some translators from repo return "type" instead of "translatorType", so the value is just remapped here.
        if let value = metadata["type"] {
            metadata["translatorType"] = value
            metadata["type"] = nil
        }
        // Same as above, but with id
        if let id = metadata["id"] {
            metadata["translatorID"] = id
            metadata["id"] = nil
        }

        return metadata
    }

    private func findDependencies(for translator: RawTranslator) -> Set<String> {
        guard let code = translator["code"] as? String else {
            DDLogError("TranslatorsAndStylesController: raw translator missing code")
            return []
        }
        guard let uuidRegex = self.uuidExpression else { return [] }

        let matches = uuidRegex.matches(in: code, options: [], range: NSRange(code.startIndex..., in: code))
        return Set(matches.compactMap({ $0.substring(at: 0, in: code).flatMap(String.init) }))
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

    /// Parses style metadata from provided XML strings and splits them into metadata and filename + XML data tuples.
    /// - styles: Array of tuples where first String is style identifier and second string is style XML.
    /// - returns: Array of styles metadata and array of tuple of filenames and xml data.
    private func split(styles: [(String, String)]) -> (styles: [Style], data: [(String, Data)]) {
        var stylesMetadata: [Style] = []
        var stylesData: [(String, Data)] = []

        for (_, xml) in styles {
            guard let data = xml.data(using: .utf8) else { continue }

            let delegate = StyleParserDelegate(filename: nil)
            let parser = XMLParser(data: data)
            parser.delegate = delegate

            guard parser.parse(), let style = delegate.style else { continue }

            stylesMetadata.append(style)
            stylesData.append((style.filename, data))
        }

        return (stylesMetadata, stylesData)
    }

    /// Parses version and indices from `deleted.txt` file and checks whether deleted version is higher than `lastDeletedVersion`. Returns data accordingly.
    /// - parameter deleted: Raw `deleted.txt` string.
    /// - parameter lastDeletedVersion: Version of `deleted.txt` file which was processed last.
    /// - returns: If `version > lastDeletedVersion` return tuple with `version` and parsed indices. Otherwise return tuple with `lastDeletedVersion` and empty array.
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

    /// Splits translators returned by repo, which contain both translators to be updated and deleted. Translators which need to be deleted have `priority = 0`, other translators have `priority > 0`.
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
    private func metadata(from translator: Translator) throws -> TranslatorMetadata {
        guard let id = translator.metadata["translatorID"] else {
            DDLogError("TranslatorsAndStylesController: translator missing id")
            throw Error.translatorMissingId
        }
        guard let rawLastUpdated = translator.metadata["lastUpdated"] else {
            DDLogError("TranslatorsAndStylesController: translator missing last updated")
            throw Error.translatorMissingLastUpdated
        }
        return try TranslatorMetadata(id: id, filename: "", rawLastUpdated: rawLastUpdated)
    }

    /// Converts `Translator` to `Data` which can be written to file.
    /// - parameter translator: Translator to be converted.
    /// - returns: Converted data.
    private func data(from translator: Translator) throws -> Data {
        let jsonMetadata: Data

        do {
            jsonMetadata = try JSONSerialization.data(withJSONObject: translator.metadata, options: .prettyPrinted)
        } catch let error {
            DDLogError("TranslatorsAndStylesController: can't create data from metadata - \(error)")
            throw Error.cantConvertTranslatorToData
        }

        guard let code = translator.code.data(using: .utf8),
              let newlines = "\n\n".data(using: .utf8) else {
            DDLogError("TranslatorsAndStylesController: can't create data from code")
            throw Error.cantConvertTranslatorToData
        }

        var data = jsonMetadata
        data.append(newlines)
        data.append(code)
        return data
    }

    private func parseStyle(from file: File) throws -> Style {
        guard let parser = XMLParser(contentsOf: file.createUrl()) else { throw Error.cantParseXmlResponse }
        let delegate = StyleParserDelegate(filename: file.name)
        parser.delegate = delegate

        if parser.parse(), let style = delegate.style {
            return style
        }

        throw Error.cantParseXmlResponse
    }

    /// Parse XML response from translator repo.
    /// - parameter data: Data to be parsed.
    /// - returns: Tupe, where first value is the "currentTime" and second value is an array of parsed `Translator`s.
    private func parseRepoResponse(from data: Data) throws -> (Int, [Translator], [(String, String)]) {
        let delegate = RepoParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        if parser.parse() {
            DDLogInfo("TranslatorsAndStylesController: parsed \(delegate.translators.count) translators and \(delegate.styles.count) styles")
            return (delegate.timestamp, delegate.translators, delegate.styles)
        }

        throw Error.cantParseXmlResponse
    }

    // MARK: - Bundle loading

    /// Load bundled index file and parse translator metadata.
    /// - returns: Parsed translator metadata.
    private func loadIndex() throws -> [TranslatorMetadata] {
        guard let url = self.bundle.url(forResource: "Bundled/translators/index", withExtension: "json") else {
            throw Error.bundleMissing
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TranslatorMetadatas.self, from: data)
        return decoded.metadatas
    }

    /// Load bundled deleted.txt file and parse version and indices stored there.
    /// - returns: Tuple, where first value is the version of deleted file and second value is an array of indices of translators to be deleted.
    private func loadDeleted() throws -> (Int, [String]) {
        return try self.loadFromBundle(resource: "Bundled/translators/deleted", type: "txt", map: {
            guard let data = self.parse(deleted: $0, lastDeletedVersion: self.lastTranslatorDeleted) else {
                throw Error.incompatibleDeleted
            }
            return data
        })
    }

    /// Load bundled last timestamp.
    /// - returns: Last timestamp.
    private func loadLastTimestamp() throws -> Int {
        return try self.loadFromBundle(resource: "Bundled/timestamp", type: "txt", map: {
            guard let value = Int($0) else { throw Error.bundleMissing }
            return value
        })
    }

    /// Load bundled last translator commit hash.
    /// - returns: Commit hash.
    private func loadLastTranslatorCommitHash() throws -> String {
        return try self.loadFromBundle(resource: "Bundled/translators/commit_hash", type: "txt", map: { return $0 })
    }

    /// Load bundled last styles commit hash.
    /// - returns: Commit hash.
    private func loadLastStylesCommitHash() throws -> String {
        return try self.loadFromBundle(resource: "Bundled/styles/commit_hash", type: "txt", map: { return $0 })
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

    func setupTest(timestamp: Int, hash: String, deleted: Int) {
        self.lastTimestamp = timestamp
        self.lastTranslatorCommitHash = hash
        self.lastTranslatorDeleted = deleted
    }
}
