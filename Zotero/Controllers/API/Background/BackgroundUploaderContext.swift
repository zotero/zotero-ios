//
//  BackgroundUploaderContext.swift
//  Zotero
//
//  Created by Michal Rentka on 06/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class BackgroundUploaderContext {
    private var uploads: [Int: BackgroundUpload] = [:]
    private let userDefault = UserDefaults(suiteName: AppGroup.identifier) ?? UserDefaults.standard

    func loadUpload(for taskId: Int) -> BackgroundUpload? {
        if let upload = self.uploads[taskId] {
            return upload
        } else if let upload = self.loadUploadFromStorage(with: taskId) {
            self.uploads[taskId] = upload
            return upload
        }
        return nil
    }

    private func loadUploadFromStorage(with taskId: Int) -> BackgroundUpload? {
        guard let data = self.userDefault.object(forKey: self.defaultsKey(for: taskId)) as? Data else { return nil }
        return try? JSONDecoder().decode(BackgroundUpload.self, from: data)
    }

    func saveUpload(_ upload: BackgroundUpload, taskId: Int) {
        self.uploads[taskId] = upload
        let data = try? JSONEncoder().encode(upload)
        self.userDefault.set(data, forKey: self.defaultsKey(for: taskId))
    }

    func deleteUpload(with taskId: Int) {
        self.uploads[taskId] = nil
        self.userDefault.removeObject(forKey: self.defaultsKey(for: taskId))
    }

    private func defaultsKey(for taskId: Int) -> String {
        return "upload_\(taskId)"
    }
}
