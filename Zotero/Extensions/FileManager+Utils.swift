//
//  FileManager+Utils.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

extension FileManager {
    func createMissingDirectories(for url: URL) throws {    
        var isDirectory: ObjCBool = false
        var exists = self.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            try self.removeItem(at: url)
            exists = false
        }

        if !exists {
            try self.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func clearDatabaseFiles(at url: URL) {
        let realmUrls = [url, url.appendingPathExtension("lock"), url.appendingPathExtension("note"), url.appendingPathExtension("management")]

        for url in realmUrls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error {
                DDLogError("FileManager: couldn't delete db file at '\(url.absoluteString)' - \(error)")
            }
        }
    }
}
