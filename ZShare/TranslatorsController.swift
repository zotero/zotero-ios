//
//  TranslatorsController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift
import Zip

typealias TranslatorInfo = [String: Any]

class TranslatorsController {
    enum Error: Swift.Error {
        case expired, bundleMissing, incompatibleString, unpackedFileEmpty, unpackedUnknownContent
    }

    @UserDefault(key: "TranslatorsNeedReload", defaultValue: false)
    static var needsReload: Bool

    let apiClient: ApiClient
    let fileStorage: FileStorage

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
    }

    func load() -> Single<[TranslatorInfo]> {
        if TranslatorsController.needsReload {
            return self.download()
                       .do(onSuccess: {
                           TranslatorsController.needsReload = false
                       })
                       .flatMap  { [weak self] in
                           guard let `self` = self else { return Single.error(Error.expired) }
                           return self.loadLocalData()
                       }
        }

        if self.fileStorage.has(Files.translators) {
            return self.loadLocalData()
        } else {
            return self.loadBundledData()
        }
    }

    private func download() -> Single<()> {
        return self.apiClient.download(request: TranslatorsRequest())
                             .flatMap { request in
                                return request.rx.response()
                             }
                             .asSingle()
                             .flatMap { [weak self] _ in
                                 guard let `self` = self else { return Single.error(Error.expired) }
                                 return self.unzipTranslators()
                             }
    }

    /// Unzip translators if possible. This method tries to:
    /// 1. Unzip files into temporary directory
    /// 2. Remove original translators directory if available
    /// 3. Move temporary directory to original destination
    /// 4. Cleanup zip file
    /// If anything breaks, it tries to cleanup temporary directory and zip file.
    /// - returns: Single which reports that translators have been successfully unpacked, Error otherwise.
    private func unzipTranslators() -> Single<()> {
        let translators = Files.translators
        let zip = Files.translatorZip
        let unpacked = Files.translatorsUnpacked

        do {
            try Zip.unzipFile(zip.createUrl(), destination: unpacked.createUrl(), overwrite: true, password: nil)
            if self.fileStorage.has(translators) {
                try self.fileStorage.remove(translators)
            }
            // Unzipping creates a folder inside our unpacked folder, find File and move its contents to translators
            let unpackedFiles: [File] = try self.fileStorage.contentsOfDirectory(at: unpacked)
            if unpackedFiles.isEmpty {
                throw Error.unpackedFileEmpty
            } else if unpackedFiles.count == 1, let content = unpackedFiles.first {
                try self.fileStorage.move(from: content, to: translators)
                try self.fileStorage.remove(unpacked)
            } else {
                if unpackedFiles.contains(where: { $0.ext == "js" }) {
                    try self.fileStorage.move(from: unpacked, to: translators)
                } else {
                    throw Error.unpackedUnknownContent
                }
            }
            try self.fileStorage.remove(zip)
            return Single.just(())
        } catch let error {
            try? self.fileStorage.remove(zip)
            try? self.fileStorage.remove(unpacked)
            return Single.error(error)
        }
    }

    private func loadLocalData() -> Single<[TranslatorInfo]> {
        return self.loadTranslators(from: Files.translators)
    }

    private func loadBundledData() -> Single<[TranslatorInfo]> {
        guard let url = Bundle.main.url(forResource: "translators",
                                        withExtension: nil,
                                        subdirectory: "translation/modules/zotero") else {
            return Single.error(Error.bundleMissing)
        }
        return self.loadTranslators(from: Files.file(from: url))
    }

    private func loadTranslators(from file: File) -> Single<[TranslatorInfo]> {
        do {
            let contents: [File] = try self.fileStorage.contentsOfDirectory(at: file)
            let translators = contents.compactMap({ self.loadTranslatorInfo(from: $0) })
            return Single.just(translators)
        } catch let error {
            NSLog("TranslatorController: error - \(error)")
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
                  var metadata = try JSONSerialization.jsonObject(with: metadataData,
                                                                  options: .allowFragments) as? [String: Any] else {
                throw Error.incompatibleString
            }

            metadata["code"] = string

            return metadata
        } catch let error {
            NSLog("TranslatorsController: cant' read data from \(file.createUrl()) - \(error)")
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
