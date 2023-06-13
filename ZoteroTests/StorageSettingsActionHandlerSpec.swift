//
//  StorageSettingsActionHandlerSpec.swift
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

final class StorageSettingsActionHandlerSpec: QuickSpec {
    // Retain realm with inMemoryIdentifier so that data are not deleted
    private let realm: Realm
    private let dbStorage: DbStorage
    private let fileCleanupController: AttachmentFileCleanupController
    private let handler: StorageSettingsActionHandler
    private var viewModel: ViewModel<StorageSettingsActionHandler>?
    private var disposeBag = DisposeBag()

    required init() {
        let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
        let dbStorage = RealmDbStorage(config: realmConfig)
        let fileCleanupController = AttachmentFileCleanupController(fileStorage: TestControllers.fileStorage, dbStorage: dbStorage)

        self.dbStorage = dbStorage
        self.fileCleanupController = fileCleanupController
        self.realm = try! Realm(configuration: realmConfig)
        self.handler = StorageSettingsActionHandler(dbStorage: dbStorage, fileStorage: TestControllers.fileStorage, fileCleanupController: fileCleanupController)
    }

    override func spec() {
        beforeEach {
            try? self.realm.write {
                self.realm.deleteAll()
            }
            self.realm.refresh()
            self.viewModel = nil
            self.disposeBag = DisposeBag()
            try? TestControllers.fileStorage.remove(Files.downloads)
        }

        describe("storage cleanup") {
            it("removes files for items in given library") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: StorageSettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 1, mbSize: 1), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! TestControllers.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! TestControllers.fileStorage.write(data, to: groupLibrary, options: .atomic)

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: StorageSettingsState(storageData: storageData), handler: self.handler)
                    self.viewModel = viewModel

                    viewModel.stateObservable
                             .subscribe(onNext: { state in
                                 guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 1 else { return }

                                 expect(TestControllers.fileStorage.has(mainLibrary)).to(beFalse())
                                 expect(TestControllers.fileStorage.has(groupLibrary)).to(beTrue())

                                 completion()
                             })
                             .disposed(by: self.disposeBag)

                    viewModel.process(action: .deleteInLibrary(.custom(.myLibrary)))
                }
            }

            it("doesn't remove files which need to be uploaded in given library") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: StorageSettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let mainLibrary2 = Files.attachmentFile(in: .custom(.myLibrary), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 2, mbSize: 2), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! TestControllers.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! TestControllers.fileStorage.write(data, to: mainLibrary2, options: .atomic)
                try! TestControllers.fileStorage.write(data, to: groupLibrary, options: .atomic)

                try! self.realm.write {
                    let group = RGroup()
                    group.identifier = 1
                    self.realm.add(group)

                    let item = RItem()
                    item.key = "bbbbbbbb"
                    item.rawType = ItemTypes.attachment
                    item.libraryId = .custom(.myLibrary)
                    item.attachmentNeedsSync = true
                    self.realm.add(item)
                }

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: StorageSettingsState(storageData: storageData), handler: self.handler)
                    self.viewModel = viewModel

                    viewModel.stateObservable
                             .subscribe(onNext: { state in
                                 guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 1 else { return }

                                 expect(TestControllers.fileStorage.has(mainLibrary)).to(beFalse())
                                 expect(TestControllers.fileStorage.has(mainLibrary2)).to(beTrue())
                                 expect(TestControllers.fileStorage.has(groupLibrary)).to(beTrue())

                                 completion()
                             })
                             .disposed(by: self.disposeBag)

                    viewModel.process(action: .deleteInLibrary(.custom(.myLibrary)))
                }
            }

            it("removes files for all items") {
                let data = try! Data(contentsOf: URL(fileURLWithPath: Bundle(for: StorageSettingsActionHandlerSpec.self).path(forResource: "bitcoin", ofType: "pdf")!))
                let mainLibrary = Files.attachmentFile(in: .custom(.myLibrary), key: "aaaaaaaa", filename: "bitcoin", contentType: "application/pdf")
                let groupLibrary = Files.attachmentFile(in: .group(1), key: "bbbbbbbb", filename: "bitcoin", contentType: "application/pdf")
                let storageData: [LibraryIdentifier: DirectoryData] = [.custom(.myLibrary): DirectoryData(fileCount: 1, mbSize: 1), .group(1): DirectoryData(fileCount: 1, mbSize: 1)]

                try! TestControllers.fileStorage.write(data, to: mainLibrary, options: .atomic)
                try! TestControllers.fileStorage.write(data, to: groupLibrary, options: .atomic)

                try! self.realm.write {
                    let group = RGroup()
                    group.identifier = 1
                    self.realm.add(group)
                }

                waitUntil(timeout: .seconds(10)) { completion in
                    let viewModel = ViewModel(initialState: StorageSettingsState(storageData: storageData), handler: self.handler)
                    self.viewModel = viewModel

                    viewModel.stateObservable
                             .subscribe(onNext: { state in
                                 guard state.storageData[.custom(.myLibrary)]?.fileCount == 0 && state.storageData[.group(1)]?.fileCount == 0 else { return }

                                 expect(TestControllers.fileStorage.has(mainLibrary)).to(beFalse())
                                 expect(TestControllers.fileStorage.has(groupLibrary)).to(beFalse())

                                 completion()
                             })
                             .disposed(by: self.disposeBag)

                    viewModel.process(action: .deleteAll)
                }
            }
        }
    }
}
