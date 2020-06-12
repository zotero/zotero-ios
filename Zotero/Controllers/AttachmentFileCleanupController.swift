//
//  AttachmentFileCleanupController.swift
//  Zotero
//
//  Created by Michal Rentka on 12/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

/// This controller listens to notification center for .attachmentDeleted notification and removes attachment files if needed.
class AttachmentFileCleanupController {
    let fileStorage: FileStorage
    private let disposeBag: DisposeBag

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
        self.disposeBag = DisposeBag()

        NotificationCenter.default
                          .rx
                          .notification(.attachmentDeleted)
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let file = notification.object as? File {
                                  self?.delete(file: file)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }

    private func delete(file: File) {
        // Don't need to check for errors, the attachment doesn't have to have the file downloaded locally, so this will throw for all attachments
        // without local files. If the file was not removed properly it can always be seen and done in settings.
        try? self.fileStorage.remove(file)
    }
}
