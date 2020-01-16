//
//  BackgroundUploaderContext.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class BackgroundUploaderContext {
    private static let key = "uploads"

    private let userDefault = UserDefaults(suiteName: AppGroup.identifier) ?? UserDefaults.standard

    var activeUploads: [BackgroundUpload] {
        return (self.userDefault.object(forKey: BackgroundUploaderContext.key) as? [Int: BackgroundUpload]).flatMap({ Array($0.values) }) ?? []
    }

    func loadUpload(for taskId: Int) -> BackgroundUpload? {
        let data = self.userDefault.object(forKey: BackgroundUploaderContext.key) as? [Int: BackgroundUpload]
        return data?[taskId]
    }

    func saveUpload(_ upload: BackgroundUpload, taskId: Int) {
        var uploads = (self.userDefault.object(forKey: BackgroundUploaderContext.key) as? [Int: BackgroundUpload]) ?? [:]
        uploads[taskId] = upload
        self.userDefault.set(uploads, forKey: BackgroundUploaderContext.key)
    }

    func deleteUpload(with taskId: Int) {
        var uploads = (self.userDefault.object(forKey: BackgroundUploaderContext.key) as? [Int: BackgroundUpload]) ?? [:]
        uploads[taskId] = nil
        self.userDefault.set(uploads, forKey: BackgroundUploaderContext.key)
    }

    func deleteAllUploads() {
        self.userDefault.removeObject(forKey: BackgroundUploaderContext.key)
    }
}
