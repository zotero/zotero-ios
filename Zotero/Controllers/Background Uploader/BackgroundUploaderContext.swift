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
    private static let sessionIdsKey = "activeUrlSessionIds"
    private static let extensionSessionIdsKey = "shareExtensionObservedUrlSessionIds"

    private let userDefault = UserDefaults.zotero

    // MARK: - Session ids

    var sessionIds: [String] {
        return self.userDefault.object([String].self, with: BackgroundUploaderContext.sessionIdsKey) ?? []
    }

    func saveSession(with identifier: String) {
        var ids = self.sessionIds
        ids.append(identifier)
        self.userDefault.set(object: ids, forKey: BackgroundUploaderContext.sessionIdsKey)
    }

    func saveSessions(with identifiers: [String]) {
        self.userDefault.set(object: identifiers, forKey: BackgroundUploaderContext.sessionIdsKey)
    }

    func deleteSession(with identifier: String) {
        var ids = self.sessionIds
        guard let index = ids.firstIndex(of: identifier) else { return }
        ids.remove(at: index)
        self.userDefault.set(object: ids, forKey: BackgroundUploaderContext.sessionIdsKey)
    }

    func deleteAllSessionIds() {
        self.userDefault.removeObject(forKey: BackgroundUploaderContext.sessionIdsKey)
    }

    var shareExtensionSessionIds: [String] {
        return self.userDefault.object([String].self, with: BackgroundUploaderContext.extensionSessionIdsKey) ?? []
    }

    func saveShareExtensionSession(with identifier: String) {
        var ids = self.shareExtensionSessionIds
        ids.append(identifier)
        self.userDefault.set(object: ids, forKey: BackgroundUploaderContext.extensionSessionIdsKey)
    }

    func saveShareExtensionSessions(with identifiers: [String]) {
        self.userDefault.set(object: identifiers, forKey: BackgroundUploaderContext.extensionSessionIdsKey)
    }

    func deleteShareExtensionSession(with identifier: String) {
        var ids = self.shareExtensionSessionIds
        guard let index = ids.firstIndex(of: identifier) else { return }
        ids.remove(at: index)
        self.userDefault.set(object: ids, forKey: BackgroundUploaderContext.extensionSessionIdsKey)
    }

    // MARK: - Uploads

    var uploads: [BackgroundUpload] {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey).flatMap({ Array($0.values) }) ?? []
    }

    var uploadsWithTaskIds: [Int: BackgroundUpload] {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
    }

    func loadUpload(for taskId: Int) -> BackgroundUpload? {
        return self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey)?[taskId]
    }

    func loadUploads(for sessionId: String) -> [(Int, BackgroundUpload)] {
        let allUploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]

        var result: [(Int, BackgroundUpload)] = []
        for (taskId, upload) in allUploads {
            guard upload.sessionId == sessionId else { continue }
            result.append((taskId, upload))
        }
        return result
    }

    func save(upload: BackgroundUpload, taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
        uploads[taskId] = upload
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func save(uploads: [Int: BackgroundUpload]) {
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func deleteUpload(with taskId: Int) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
        uploads[taskId] = nil
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func deleteUploads(with taskIds: [Int]) {
        var uploads = self.userDefault.object([Int: BackgroundUpload].self, with: BackgroundUploaderContext.activeKey) ?? [:]
        for taskId in taskIds {
            uploads[taskId] = nil
        }
        self.userDefault.set(object: uploads, forKey: BackgroundUploaderContext.activeKey)
    }

    func deleteAllUploads() {
        self.userDefault.removeObject(forKey: BackgroundUploaderContext.activeKey)
    }
}
