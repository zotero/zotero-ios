//
//  BackgroundUploaderContext.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class BackgroundUploaderContext {
    private static let key = "uploads"

    private let userDefault = UserDefaults.zotero

    // MARK: - Actions

    var activeUploads: [BackgroundUpload] {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.key).flatMap({ Array($0.values) }) ?? []
    }

    func loadUpload(for taskId: Int) -> BackgroundUpload? {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.key)?[taskId]
    }

    func saveUpload(_ upload: BackgroundUpload, taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.key) ?? [:]
        uploads[taskId] = upload
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.key)
    }

    func deleteUpload(with taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.key) ?? [:]
        uploads[taskId] = nil
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.key)
    }

    func deleteUploads(with taskIds: [Int]) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.key) ?? [:]
        for id in taskIds {
            uploads[id] = nil
        }
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.key)
    }

    func deleteAllUploads() {
        self.userDefault.removeObject(forKey: BackgroundUploaderContext.key)
    }
}
