//
//  SyncSettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct SyncSettingsActionHandler: ViewModelActionHandler {
    typealias Action = SyncSettingsAction
    typealias State = SyncSettingsState

    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let webDavController: WebDavController
    private unowned let sessionController: SessionController
    private unowned let syncScheduler: SynchronizationScheduler

    init(dbStorage: DbStorage, fileStorage: FileStorage, sessionController: SessionController, webDavController: WebDavController, syncScheduler: SynchronizationScheduler) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.sessionController = sessionController
        self.webDavController = webDavController
        self.syncScheduler = syncScheduler
    }

    func process(action: SyncSettingsAction, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        switch action {
        case .logout:
            self.sessionController.reset()

        case .setFileSyncType(let type):
            self.set(fileSyncType: type, in: viewModel)

        case .setScheme(let scheme):
            self.update(viewModel: viewModel) { state in
                state.scheme = scheme
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.scheme = scheme
            self.webDavController.resetVerification()

        case .setUrl(let url):
            self.update(viewModel: viewModel) { state in
                state.url = url
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.url = url
            self.webDavController.resetVerification()

        case .setUsername(let username):
            self.update(viewModel: viewModel) { state in
                state.username = username
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.username = username
            self.webDavController.resetVerification()

        case .setPassword(let password):
            self.update(viewModel: viewModel) { state in
                state.password = password
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.password = password
            self.webDavController.resetVerification()

        case .verify:
            self.verify(in: viewModel)

        case .cancelVerification:
            self.cancelVerification(viewModel: viewModel)
        }
    }

    private func cancelVerification(viewModel: ViewModel<SyncSettingsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.isVerifyingWebDav = false
            state.apiDisposeBag = DisposeBag()
        }
    }

    private func set(fileSyncType type: SyncSettingsState.FileSyncType, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        guard viewModel.state.fileSyncType != type else { return }

        self.syncScheduler.cancelSync()

        do {
            let keys = self.downloadedAttachmentKeys()

            var requests: [DbRequest] = [MarkAttachmentsNotUploadedDbRequest(keys: keys, libraryId: .custom(.myLibrary))]
            if type == .zotero {
                requests.append(DeleteAllWebDavDeletionsDbRequest())
            }

            try self.dbStorage.createCoordinator().perform(requests: requests)

            self.update(viewModel: viewModel) { state in
                state.fileSyncType = type
            }
            self.webDavController.sessionStorage.isEnabled = type == .webDav

            if type == .zotero {
                self.syncScheduler.request(syncType: .normal)
            }
        } catch let error {
            DDLogError("SyncSettingsActionHandler: can't mark all attachments not uploaded - \(error)")
        }
    }

    private func downloadedAttachmentKeys() -> [String] {
        guard let contents: [File] = try? self.fileStorage.contentsOfDirectory(at: Files.downloads(for: .custom(.myLibrary))) else { return [] }
        return contents.filter({ file in
                           if file.relativeComponents.count == 3 && (file.relativeComponents.last ?? "").count == KeyGenerator.length {
                               // Check whether folder actually contains an attachment to avoid "attachment missing" errors.
                               let contents: [URL] = (try? self.fileStorage.contentsOfDirectory(at: file)) ?? []
                               return contents.count > 0
                           }
                           return false
                       })
                       .compactMap({ $0.relativeComponents.last })
    }

    private func verify(in viewModel: ViewModel<SyncSettingsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.isVerifyingWebDav = true
        }

        self.webDavController.checkServer(queue: .main)
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(with: viewModel, onSuccess: { viewModel, _ in
                self.update(viewModel: viewModel) { state in
                    state.isVerifyingWebDav = false
                    state.webDavVerificationResult = .success(())
                }

                self.syncScheduler.request(syncType: .normal)
            }, onFailure: { viewModel, error in
                self.update(viewModel: viewModel) { state in
                    state.isVerifyingWebDav = false
                    state.webDavVerificationResult = .failure(error)
                }
            })
            .disposed(by: viewModel.state.apiDisposeBag)
    }
}

