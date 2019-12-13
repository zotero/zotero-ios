//
//  TranslatorsController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

typealias TranslatorInfo = [String: Any]

class TranslatorsController {
    enum Error: Swift.Error {
        case bundleMissing, incompatibleString
    }

    let fileStorage: FileStorage

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
    }

    func load() -> Single<[TranslatorInfo]> {
        return self.loadBundledData()
    }

    private func loadBundledData() -> Single<[TranslatorInfo]> {
        guard let url = Bundle.main.url(forResource: "translators",
                                        withExtension: nil,
                                        subdirectory: "translation/modules/zotero") else {
            return Single.error(Error.bundleMissing)
        }

        do {
            let contents = try self.fileStorage.contentsOfDirectory(at: Files.file(from: url))
            let translators = contents.compactMap({ self.loadTranslatorInfo(from: $0) })
            return Single.just(translators)
        } catch let error {
            NSLog("TranslatorController: error - \(error)")
            return Single.error(error)
        }
    }

    private func loadTranslatorInfo(from file: File) -> TranslatorInfo? {
        do {
            let data = try self.fileStorage.read(file)
            guard let string = String(data: data, encoding: .utf8),
                  let endingIndex = string.firstIndex(of: "}").flatMap({ string.index($0, offsetBy: 1) }),
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
}
