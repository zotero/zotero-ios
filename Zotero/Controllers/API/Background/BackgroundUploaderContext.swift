//
//  BackgroundUploaderContext.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class BackgroundUploaderContext {
    /// Key for uploads that are not yet uploaded.
    private static let activeKey = "uploads"

    private let userDefault = UserDefaults.zotero

    // MARK: - Actions

    var uploads: [BackgroundUpload] {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey).flatMap({ Array($0.values) }) ?? []
    }

    func loadUpload(for taskId: Int) -> BackgroundUpload? {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey)?[taskId]
    }

    func save(upload: BackgroundUpload, taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
        uploads[taskId] = upload
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func deleteUpload(with taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
        uploads[taskId] = nil
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func deleteAllUploads() {
        self.userDefault.removeObject(forKey: BackgroundUploaderContext.activeKey)
    }
}
