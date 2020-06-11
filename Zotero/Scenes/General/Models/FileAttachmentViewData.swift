//
//  FileAttachmentViewData.swift
//  Zotero
//
//  Created by Michal Rentka on 11/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct FileAttachmentViewData {
    let state: FileAttachmentView.State
    let type: FileAttachmentView.Kind

    init?(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?) {
        switch contentType {
        case .file(let file, _, let location):
            let (state, type) = FileAttachmentViewData.data(fromFile: file, location: location, progress: progress, error: error)
            self.state = state
            self.type = type
        case .url:
            return nil
        }
    }

    init(state: FileAttachmentView.State, type: FileAttachmentView.Kind) {
        self.state = state
        self.type = type
    }

    private static func data(fromFile file: File, location: Attachment.FileLocation?,
                             progress: CGFloat?, error: Error?) -> (FileAttachmentView.State, FileAttachmentView.Kind) {
        let type: FileAttachmentView.Kind
        switch file.ext {
        case "pdf":
            type = .pdf
        default:
            type = .document
        }

        if error != nil {
            return (.failed, type)
        }
        if let progress = progress {
            return (.progress(progress), type)
        }

        let state: FileAttachmentView.State
        if let location = location {
            switch location {
            case .local:
                state = .downloaded
            case .remote:
                state = .downloadable
            }
        } else {
            state = .missing
        }

        return (state, type)
    }
}
