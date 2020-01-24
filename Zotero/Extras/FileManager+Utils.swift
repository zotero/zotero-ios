//
//  FileManager+Utils.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

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
}
