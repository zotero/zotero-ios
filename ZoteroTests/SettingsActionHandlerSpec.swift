//
//  SettingsActionHandlerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 31.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//


@testable import Zotero

import Foundation

import Nimble
import RealmSwift
import RxSwift
import Quick

final class SettingsActionHandlerSpec: QuickSpec {
    private static let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
    private static let realm = try! Realm(configuration: realmConfig) // Retain realm with inMemoryIdentifier so that data are not deleted
    private static let dbStorage = RealmDbStorage(config: SettingsActionHandlerSpec.realmConfig)
    private static let fileStorage = FileStorageController()
    private static let sessionController = SessionController(secureStorage: KeychainSecureStorage(), defaults: Defaults.shared)
    private static let websocketController = WebSocketController(dbStorage: dbStorage)
    private static let apiClient = ZoteroApiClient(baseUrl: "http://zotero.org/", configuration: .default)
    private static let backgroundUploader = BackgroundUploader(uploadProcessor: BackgroundUploadProcessor(apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage), schemaVersion: 0)
    private static let syncScheduler = SyncScheduler(controller: SyncController(userId: 0, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, schemaController: SchemaController(),
                                                                                dateParser: DateParser(), backgroundUploader: backgroundUploader, syncDelayIntervals: [], conflictDelays: []))
    private static let debugLogging = DebugLogging(apiClient: apiClient, fileStorage: fileStorage)
    private static let translatorsController = TranslatorsController(apiClient: apiClient, indexStorage: dbStorage, fileStorage: fileStorage)
    private static let fileCleanupController = AttachmentFileCleanupController(fileStorage: fileStorage, dbStorage: dbStorage)
    private static let handler = SettingsActionHandler(dbStorage: dbStorage, fileStorage: fileStorage, sessionController: sessionController, webSocketController: websocketController,
                                                       syncScheduler: syncScheduler, debugLogging: debugLogging, translatorsController: translatorsController,
                                                       fileCleanupController: fileCleanupController)
    private static var viewModel: ViewModel<SettingsActionHandler>?
    private static var disposeBag = DisposeBag()

    override func spec() {
        beforeEach {
            try? SettingsActionHandlerSpec.realm.write {
                SettingsActionHandlerSpec.realm.deleteAll()
            }
            SettingsActionHandlerSpec.realm.refresh()
            SettingsActionHandlerSpec.viewModel = nil
            SettingsActionHandlerSpec.disposeBag = DisposeBag()
            try? SettingsActionHandlerSpec.fileStorage.remove(Files.downloads)
        }

        describe("storage cleanup") {
            it("removes files for items in given library") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: SettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 1, mbSize: 1), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! SettingsActionHandlerSpec.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! SettingsActionHandlerSpec.fileStorage.write(data, to: groupLibrary, options: .atomic)

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: SettingsState(storageData: storageData), handler: SettingsActionHandlerSpec.handler)
                    SettingsActionHandlerSpec.viewModel = viewModel

                    viewModel.stateObservable
                        .subscribe(onNext: { state in
                            guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 1 else {
                                return
                            }

                            expect(SettingsActionHandlerSpec.fileStorage.has(mainLibrary)).to(beFalse())
                            expect(SettingsActionHandlerSpec.fileStorage.has(groupLibrary)).to(beTrue())

                            completion()
                        })
                        .disposed(by: SettingsActionHandlerSpec.disposeBag)

                    viewModel.process(action: .deleteDownloadsInLibrary(.custom(.myLibrary)))
                }
            }

            it("doesn't remove files which need to be uploaded in given library") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: SettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let mainLibrary2 = Files.attachmentFile(in: .custom(.myLibrary), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 2, mbSize: 2), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! SettingsActionHandlerSpec.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! SettingsActionHandlerSpec.fileStorage.write(data, to: mainLibrary2, options: .atomic)
                try! SettingsActionHandlerSpec.fileStorage.write(data, to: groupLibrary, options: .atomic)

                try! SettingsActionHandlerSpec.realm.write {
                    let group = RGroup()
                    group.identifier = 1
                    SettingsActionHandlerSpec.realm.add(group)

                    let item = RItem()
                    item.key = "bbbbbbbb"
                    item.rawType = ItemTypes.attachment
                    item.libraryId = .custom(.myLibrary)
                    item.attachmentNeedsSync = true
                    SettingsActionHandlerSpec.realm.add(item)
                }

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: SettingsState(storageData: storageData), handler: SettingsActionHandlerSpec.handler)
                    SettingsActionHandlerSpec.viewModel = viewModel

                    viewModel.stateObservable
                        .subscribe(onNext: { state in
                            guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 1 else {
                                return
                            }

                            expect(SettingsActionHandlerSpec.fileStorage.has(mainLibrary)).to(beFalse())
                            expect(SettingsActionHandlerSpec.fileStorage.has(mainLibrary2)).to(beTrue())
                            expect(SettingsActionHandlerSpec.fileStorage.has(groupLibrary)).to(beTrue())

                            completion()
                        })
                        .disposed(by: SettingsActionHandlerSpec.disposeBag)

                    viewModel.process(action: .deleteDownloadsInLibrary(.custom(.myLibrary)))
                }
            }

            it("removes files for all items") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: SettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 1, mbSize: 1), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! SettingsActionHandlerSpec.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! SettingsActionHandlerSpec.fileStorage.write(data, to: groupLibrary, options: .atomic)

                try! SettingsActionHandlerSpec.realm.write {
                    let group = RGroup()
                    group.identifier = 1
                    SettingsActionHandlerSpec.realm.add(group)
                }

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: SettingsState(storageData: storageData), handler: SettingsActionHandlerSpec.handler)
                    SettingsActionHandlerSpec.viewModel = viewModel

                    viewModel.stateObservable
                        .subscribe(onNext: { state in
                            guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 0 else {
                                return
                            }

                            expect(SettingsActionHandlerSpec.fileStorage.has(mainLibrary)).to(beFalse())
                            expect(SettingsActionHandlerSpec.fileStorage.has(groupLibrary)).to(beFalse())

                            completion()
                        })
                        .disposed(by: SettingsActionHandlerSpec.disposeBag)

                    viewModel.process(action: .deleteAllDownloads)
                }
            }
        }
    }
}
