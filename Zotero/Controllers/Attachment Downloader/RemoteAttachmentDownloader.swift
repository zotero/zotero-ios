//
//  RemoteAttachmentDownloader.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import RxSwift

final class RemoteAttachmentDownloader {
    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, fileStorage: FileStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.disposeBag = DisposeBag()
    }

    func download(data: [(Attachment, URL, String)]) {

    }
}
