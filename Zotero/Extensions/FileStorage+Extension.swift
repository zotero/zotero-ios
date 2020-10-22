//
//  FileStorage+Extension.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension FileStorage {
    /// Copy attachments from file picker url (external app sandboxes) to our internal url (our app sandbox)
    /// - parameter attachments: Attachments which will be copied if needed
    func copyAttachmentFilesIfNeeded(for attachments: [Attachment]) throws {
        for attachment in attachments {
            switch attachment.contentType {
            case .url, .snapshot: continue
            case .file(let originalFile, _, _):
                let newFile = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, ext: originalFile.ext)
                // Make sure that the file was not already moved to our internal location before
                guard originalFile.createUrl() != newFile.createUrl() else { continue }

                try self.copy(from: originalFile, to: newFile)
            }
        }
    }
}
