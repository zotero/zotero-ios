//
//  CustomURLController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

enum CustomURLAction: String {
    case select = "select"
    case openPdf = "open-pdf"
}

final class CustomURLController {
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let downloader: AttachmentDownloader

    private var disposeBag: DisposeBag?

    init(dbStorage: DbStorage, fileStorage: FileStorage, downloader: AttachmentDownloader) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.downloader = downloader
    }

    func process(url: URL, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "zotero", let action = components.host.flatMap({ CustomURLAction(rawValue: $0) }) else { return }

        switch action {
        case .select:
            self.select(path: components.path, coordinatorDelegate: coordinatorDelegate, animated: animated)

        case .openPdf:
            self.openPdf(path: components.path, queryItems: components.queryItems ?? [], coordinatorDelegate: coordinatorDelegate, animated: animated)
        }
    }

    private func select(path: String, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items" else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return
            }
            self.showItemIfPossible(key: parts[3], libraryId: .custom(.myLibrary), coordinatorDelegate: coordinatorDelegate, animated: animated)

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return
            }
            self.showItemIfPossible(key: parts[4], libraryId: .group(groupId), coordinatorDelegate: coordinatorDelegate, animated: animated)

        default: break
        }
    }

    private func showItemIfPossible(key: String, libraryId: LibraryIdentifier, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        do {
            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)

            coordinatorDelegate.showItemDetail(key: (item.parent?.key ?? item.key), library: library, selectChildKey: item.key, animated: animated)
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
        }
    }

    private func openPdf(path: String, queryItems: [URLQueryItem], coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        let parts = path.components(separatedBy: "/")

        guard parts.count > 2 else {
            DDLogError("CustomURLController: path invalid - \(path)")
            return
        }

        switch parts[1] {
        case "library":
            guard parts.count == 4, parts[2] == "items", let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for user library - \(path)")
                return
            }
            self.openPdfIfPossible(on: page, key: parts[3], libraryId: .custom(.myLibrary), coordinatorDelegate: coordinatorDelegate, animated: animated)

        case "groups":
            guard parts.count == 5, parts[3] == "items", let groupId = Int(parts[2]), let queryItem = queryItems.first, queryItem.name == "page", let page = queryItem.value.flatMap(Int.init) else {
                DDLogError("CustomURLController: path invalid for group - \(path)")
                return
            }
            self.openPdfIfPossible(on: page, key: parts[4], libraryId: .group(groupId), coordinatorDelegate: coordinatorDelegate, animated: animated)

        default:
            guard parts.count == 3 else {
                DDLogError("CustomURLController: path invalid for ZotFile format - \(path)")
                return
            }
            let zotfileParts = parts[1].components(separatedBy: "_")
            guard zotfileParts.count == 2, let groupId = Int(zotfileParts[0]) else {
                DDLogError("CustomURLController: wrong library format in ZotFile format - \(path)")
                return
            }
            guard let page = Int(parts[2]) else {
                DDLogError("CustomURLController: page missing in ZotFile format - \(path)")
                return
            }

            let libraryId: LibraryIdentifier = groupId == 0 ? .custom(.myLibrary) : .group(groupId)
            self.openPdfIfPossible(on: page, key: zotfileParts[1], libraryId: libraryId, coordinatorDelegate: coordinatorDelegate, animated: animated)
        }
    }

    private func openPdfIfPossible(on page: Int, key: String, libraryId: LibraryIdentifier, coordinatorDelegate: CustomURLCoordinatorDelegate, animated: Bool) {
        do {
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key), on: .main)

            guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: self.fileStorage, urlDetector: nil) else {
                DDLogInfo("CustomURLConverter: trying to open incorrect item - \(item.rawType)")
                return
            }

            guard case .file(_, let contentType, let location, _) = attachment.type, contentType == "application/pdf" else {
                DDLogInfo("CustomURLConverter: trying to open \(attachment.type) instead of pdf")
                return
            }

            let library = try self.dbStorage.perform(request: ReadLibraryDbRequest(libraryId: libraryId), on: .main)
            let parentKey = item.parent?.key

            switch location {
            case .local:
                coordinatorDelegate.open(attachment: attachment, library: library, on: page, parentKey: parentKey, animated: animated)

            case .remote, .localAndChangedRemotely:
                coordinatorDelegate.showItemDetail(key: (parentKey ?? item.key), library: library, selectChildKey: item.key, animated: animated)
                self.download(attachment: attachment, parentKey: parentKey) { [weak coordinatorDelegate] in
                    coordinatorDelegate?.open(attachment: attachment, library: library, on: page, parentKey: parentKey, animated: true)
                }

            case .remoteMissing:
                DDLogInfo("CustomURLConverter: attachment \(attachment.key) missing remotely")
            }
        } catch let error {
            DDLogError("CustomURLConverter: library (\(libraryId)) or item (\(key)) not found - \(error)")
        }
    }

    private func download(attachment: Attachment, parentKey: String?, completion: @escaping () -> Void) {
        let disposeBag = DisposeBag()

        self.downloader.observable
                       .observe(on: MainScheduler.instance)
                       .subscribe(onNext: { [weak self] update in
                           guard let `self` = self, update.libraryId == attachment.libraryId && update.key == attachment.key else { return }

                           switch update.kind {
                           case .ready:
                               completion()
                               self.disposeBag = nil
                           case .cancelled, .failed:
                               self.disposeBag = nil
                           case .progress: break
                           }
                       })
                       .disposed(by: disposeBag)

        self.disposeBag = disposeBag
        self.downloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)
    }
}
