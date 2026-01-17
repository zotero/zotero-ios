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
    private let backgroundQueue: DispatchQueue
    private weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    init(dbStorage: DbStorage, fileStorage: FileStorage, sessionController: SessionController, webDavController: WebDavController, syncScheduler: SynchronizationScheduler,
         coordinatorDelegate: SettingsCoordinatorDelegate?) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.sessionController = sessionController
        self.webDavController = webDavController
        self.syncScheduler = syncScheduler
        self.coordinatorDelegate = coordinatorDelegate
        self.backgroundQueue = DispatchQueue(label: "org.zotero.SyncSettingsActionHandler.background", qos: .userInteractive)
        
        // Certificate storage now handled automatically by WebDavController
        self.webDavController.onServerTrustChallenge = { [weak coordinatorDelegate] trust, host, completion in
            DispatchQueue.main.async {
                coordinatorDelegate?.promptServerTrust(trust: trust, host: host, completion: completion)
            }
        }
    }

    func process(action: SyncSettingsAction, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        switch action {
        case .logout:
            self.sessionController.reset()

        case .setFileSyncType(let type):
            self.set(fileSyncType: type, in: viewModel)

        case .setScheme(let scheme):
            guard scheme != viewModel.state.scheme else { break }
            self.update(viewModel: viewModel) { state in
                state.scheme = scheme
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.scheme = scheme
            self.webDavController.resetVerification()

        case .setUrl(let url):
            guard url != viewModel.state.url else { break }
            self.set(url: url, in: viewModel)

        case .setUsername(let username):
            guard username != viewModel.state.username else { break }
            self.update(viewModel: viewModel) { state in
                state.username = username
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.username = username
            self.webDavController.resetVerification()

        case .setPassword(let password):
            guard password != viewModel.state.password else { break }
            self.update(viewModel: viewModel) { state in
                state.password = password
                state.webDavVerificationResult = nil
            }
            self.webDavController.sessionStorage.password = password
            self.webDavController.resetVerification()

        case .verify:
            trimURLIfNeeded(in: viewModel)
            self.verify(tryCreatingZoteroDir: false, in: viewModel)

        case .cancelVerification:
            self.cancelVerification(viewModel: viewModel)

        case .createZoteroDirectory: break

        case .cancelZoteroDirectoryCreation: break

        case .recheckKeys:
            if self.syncScheduler.inProgress.value {
                self.syncScheduler.cancelSync()
            }
            self.observeSyncIssues(in: viewModel)
            self.syncScheduler.request(sync: .keysOnly, libraries: .all)

        case .dismiss:
            trimURLIfNeeded(in: viewModel)
        }
    }

    /// Observes result of keys only sync, if we're getting Forbidden (403) now, log the user out
    private func observeSyncIssues(in viewModel: ViewModel<SyncSettingsActionHandler>) {
        self.syncScheduler.syncController
                          .progressObservable
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak viewModel] progress in
                              guard let viewModel = viewModel else { return }
                              self.process(syncProgress: progress, in: viewModel)
                          })
                          .disposed(by: viewModel.state.apiDisposeBag)
    }

    private func process(syncProgress progress: SyncProgress, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        switch progress {
        case .aborted(let fatalError):
            if case .forbidden = fatalError {
                self.sessionController.reset()
            }
            self.update(viewModel: viewModel) { state in
                state.apiDisposeBag = DisposeBag()
            }

        case .finished:
            self.update(viewModel: viewModel) { state in
                state.apiDisposeBag = DisposeBag()
            }

        default: break
        }
    }

    private func set(url: String, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        var decodedUrl = url
        if url.contains("%") {
            decodedUrl = url.removingPercentEncoding ?? url
        }
        webDavController.sessionStorage.url = decodedUrl
        webDavController.resetVerification()

        update(viewModel: viewModel) { state in
            state.url = url
            state.webDavVerificationResult = nil
            state.markingForReupload = true
        }

        markAttachmentsForReupload(for: .webDav) { _ in
            update(viewModel: viewModel) { state in
                state.markingForReupload = false
            }
        }
    }

    private func cancelVerification(viewModel: ViewModel<SyncSettingsActionHandler>) {
        update(viewModel: viewModel) { state in
            state.isVerifyingWebDav = false
            state.apiDisposeBag = DisposeBag()
        }
    }

    private func set(fileSyncType type: SyncSettingsState.FileSyncType, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        guard viewModel.state.fileSyncType != type else { return }

        syncScheduler.cancelSync()

        let oldType = viewModel.state.fileSyncType

        update(viewModel: viewModel) { state in
            state.fileSyncType = type
            state.markingForReupload = true
        }

        markAttachmentsForReupload(for: type) { error in
            update(viewModel: viewModel) { state in
                if error != nil {
                    state.fileSyncType = oldType
                    // TODO: show error
                }
                state.markingForReupload = false
            }

            guard error == nil else { return }

            webDavController.sessionStorage.isEnabled = type == .webDav

            if type == .zotero {
                if syncScheduler.inProgress.value {
                    syncScheduler.cancelSync()
                }
                syncScheduler.request(sync: .normal, libraries: .all)
            }
        }
    }

    private func markAttachmentsForReupload(for type: SyncSettingsState.FileSyncType, completion: @escaping (Error?) -> Void) {
        backgroundQueue.async {
            do {
                try performMark(for: type)
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error {
                DDLogError("SyncSettingsActionHandler: can't mark all attachments not uploaded - \(error)")
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }

        func performMark(for type: SyncSettingsState.FileSyncType) throws {
            let keys = downloadedAttachmentKeys()
            var requests: [DbRequest] = [MarkAttachmentsNotUploadedDbRequest(keys: keys, libraryId: .custom(.myLibrary))]
            if type == .zotero {
                requests.append(DeleteAllWebDavDeletionsDbRequest())
            }
            try dbStorage.perform(writeRequests: requests, on: backgroundQueue)
        }
    }

    private func downloadedAttachmentKeys() -> [String] {
        guard let contents: [File] = try? self.fileStorage.contentsOfDirectory(at: Files.downloads(for: .custom(.myLibrary))) else { return [] }
        return contents.filter({ file in
                           if file.relativeComponents.count == 3 && (file.relativeComponents.last ?? "").count == KeyGenerator.length {
                               // Check whether folder actually contains an attachment to avoid "attachment missing" errors.
                               let contents: [URL] = (try? self.fileStorage.contentsOfDirectory(at: file)) ?? []
                               return !contents.isEmpty
                           }
                           return false
                       })
                       .compactMap({ $0.relativeComponents.last })
    }

    private func verify(tryCreatingZoteroDir: Bool, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        if !viewModel.state.isVerifyingWebDav {
            self.update(viewModel: viewModel) { state in
                state.isVerifyingWebDav = true
            }
        }

        let initial: Single<()>
        if tryCreatingZoteroDir {
            initial = self.webDavController.createZoteroDirectory(queue: .main)
        } else {
            initial = .just(())
        }

        initial.flatMap { _ in self.webDavController.checkServer(queue: .main) }
               .subscribe(on: MainScheduler.instance)
               .observe(on: MainScheduler.instance)
               .subscribe(with: viewModel, onSuccess: { viewModel, _ in
                   self.update(viewModel: viewModel) { state in
                       state.isVerifyingWebDav = false
                       state.webDavVerificationResult = .success(())
                   }
                   if self.syncScheduler.inProgress.value {
                       self.syncScheduler.cancelSync()
                   }
                   self.syncScheduler.request(sync: .normal, libraries: .all)
               }, onFailure: { viewModel, error in
                   self.handleVerification(error: error, in: viewModel)
               })
               .disposed(by: viewModel.state.apiDisposeBag)
    }

    private func handleVerification(error: Error, in viewModel: ViewModel<SyncSettingsActionHandler>) {
        if let delegate = coordinatorDelegate, let error = error as? WebDavError.Verification, case .zoteroDirNotFound(let url) = error {
            delegate.promptZoteroDirCreation(url: url,
                                             create: {
                                                 self.verify(tryCreatingZoteroDir: true, in: viewModel)
                                             },
                                             cancel: {
                                                 self.update(viewModel: viewModel) { state in
                                                     state.webDavVerificationResult = .failure(error)
                                                     state.isVerifyingWebDav = false
                                                 }
                                             })
            return
        }

        self.update(viewModel: viewModel) { state in
            state.webDavVerificationResult = .failure(error)
            state.isVerifyingWebDav = false
        }
    }

    private func trimURLIfNeeded(in viewModel: ViewModel<SyncSettingsActionHandler>) {
        let trimmedURL = viewModel.state.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedURL != viewModel.state.url else { return }
        set(url: trimmedURL, in: viewModel)
    }
}
