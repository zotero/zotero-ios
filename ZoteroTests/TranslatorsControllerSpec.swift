//
//  TranslatorsControllerSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 06/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import Foundation

import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift
import RxSwift
import RealmSwift
import Quick

class TranslatorsControllerSpec: QuickSpec {
    private let baseUrl = URL(string: ApiConstants.baseUrlString)!
    private let version = TranslatorsControllerSpec.createVersion()
    private let fileStorage: FileStorageController = FileStorageController()
    private var dbConfig: Realm.Configuration!
    private let bundledTimestamp = 1585834479
    private let translatorId = "bbf1617b-d836-4665-9aae-45f223264460"
    private let bundledTranslatorTimestamp = 1471546264 // 2016-08-18 20:51:04
    private let remoteTranslatorTimestamp = 1586181600 // 2020-04-06 16:00:00
    private let remoteTimestamp = 1586182261 // 2020-04-06 16:00:00
    // We need to retain realm with memory identifier so that data are not deleted
    private var realm: Realm!
    private var controller: TranslatorsController!
    private var disposeBag: DisposeBag!

    override func spec() {
        beforeEach {
            self.dbConfig = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
            self.realm = try! Realm(configuration: self.dbConfig)
            self.controller = TranslatorsControllerSpec.createController(dbConfig: self.dbConfig)
            self.disposeBag = DisposeBag()
            try? self.fileStorage.remove(Files.translators)
            HTTPStubs.removeAllStubs()
        }

        it("Loads bundled data") {
            // Stub to "disable" remote request
            let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(self.bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Setup as first-time update
            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(Double(self.bundledTimestamp)))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()
                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp))))
                        expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beTrue())

                        self.controller.translators()
                            .observeOn(MainScheduler.instance)
                            .subscribe(onSuccess: { translators in
                                expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                                doneAction()
                            }, onError: { error in
                                fail("Could not load translators: \(error)")
                                doneAction()
                            })
                            .disposed(by: self.disposeBag)
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Updates existing outdated data with newer bundled data") {
            // Stub to "disable" remote request
            let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(self.bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.startup.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Create local records
            self.controller.setupTest(timestamp: self.bundledTimestamp - 100, hash: "123abc", deleted: 0)

            try! self.realm.write {
                let translator = RTranslatorMetadata()
                translator.id = self.translatorId
                translator.lastUpdated = Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp - 100))
                self.realm.add(translator)
            }

            let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "bundled/translators/translator", withExtension: "js")!
            try! self.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: self.translatorId))

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(Double(self.bundledTimestamp)))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()
                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp))))
                        expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beTrue())

                        self.controller.translators()
                            .observeOn(MainScheduler.instance)
                            .subscribe(onSuccess: { translators in
                                expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                                doneAction()
                            }, onError: { error in
                                fail("Could not load translators: \(error)")
                                doneAction()
                            })
                            .disposed(by: self.disposeBag)
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Doesn't update newer existing data with outdated bundled data") {
            // Stub to "disable" remote request
            let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(self.bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.startup.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Create local records
            self.controller.setupTest(timestamp: self.bundledTimestamp, hash: "123abc", deleted: 0)

            try! self.realm.write {
                let translator = RTranslatorMetadata()
                translator.id = self.translatorId
                translator.lastUpdated = Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp + 100))
                self.realm.add(translator)
            }

            let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "bundled/translators/translator", withExtension: "js")!
            try! self.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: self.translatorId))

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(Double(self.bundledTimestamp)))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()
                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp + 100))))
                        expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beTrue())

                        self.controller.translators()
                            .observeOn(MainScheduler.instance)
                            .subscribe(onSuccess: { translators in
                                expect(translators.first?["browserSupport"] as? String).to(equal("gcsi"))
                                doneAction()
                            }, onError: { error in
                                fail("Could not load translators: \(error)")
                                doneAction()
                            })
                            .disposed(by: self.disposeBag)
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Removes translator with bundle update") {
            // Stub to "disable" remote request
            let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(self.bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.startup.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Create local records
            let deletedTranslatorId = "96b9f483-c44d-5784-cdad-ce21b984"

            self.controller.setupTest(timestamp: self.bundledTimestamp - 100, hash: "abc123", deleted: 0)

            try! self.realm.write {
                let translator = RTranslatorMetadata()
                translator.id = deletedTranslatorId
                translator.lastUpdated = Date(timeIntervalSince1970: Double(self.remoteTranslatorTimestamp))
                self.realm.add(translator)
            }

            let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "bundled/translators/translator", withExtension: "js")!
            try! self.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: deletedTranslatorId))

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()

                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", deletedTranslatorId).first

                        expect(translator).to(beNil())
                        expect(self.fileStorage.has(Files.translator(filename: deletedTranslatorId))).to(beFalse())

                        doneAction()
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Loads remote data") {
            // Stub to return remote translator
            let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators", withExtension: "xml")
            let response = try! String(contentsOf: responseUrl!)
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Setup as first-time update
            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(Double(self.remoteTimestamp)))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()

                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(self.remoteTranslatorTimestamp))))
                        expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beTrue())

                        self.controller.translators()
                            .observeOn(MainScheduler.instance)
                            .subscribe(onSuccess: { translators in
                                expect(translators.first?["browserSupport"] as? String).to(equal("gcsi"))
                                doneAction()
                            }, onError: { error in
                                fail("Could not load translators: \(error)")
                                doneAction()
                            })
                            .disposed(by: self.disposeBag)
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Removes translator with remote update") {
            // Stup to return remove translator with priority=0
            let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators_delete", withExtension: "xml")
            let response = try! String(contentsOf: responseUrl!)
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            // Setup as first-time update so that there is a bundle update as well
            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            // Perform update and wait for results
            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()

                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

                        expect(translator).to(beNil())
                        expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beFalse())

                        doneAction()
                    }, onError: { error in
                        fail("Could not finish loading: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)

                self.controller.update()
            }
        }

        it("Resets to bundled data") {
            // Create local records
            self.controller.setupTest(timestamp: 1586185643, hash: "123abc", deleted: 0)

            try! self.realm.write {
                let translator = RTranslatorMetadata()
                translator.id = self.translatorId
                translator.lastUpdated = Date(timeIntervalSince1970: Double(self.remoteTranslatorTimestamp))
                self.realm.add(translator)
            }

            let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "bundled/translators/translator", withExtension: "js")!
            try! self.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: self.translatorId))

            // Perform reset
            self.controller.resetToBundle()

            // Check whether translator was reverted to bundled data
            let translator = self.realm.objects(RTranslatorMetadata.self).filter("id = %@", self.translatorId).first

            expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(Double(self.bundledTimestamp)))
            expect(translator).toNot(beNil())
            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(self.bundledTranslatorTimestamp))))
            expect(self.fileStorage.has(Files.translator(filename: self.translatorId))).to(beTrue())

            waitUntil(timeout: 10) { doneAction in
                self.controller.translators()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { translators in
                        expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                        doneAction()
                    }, onError: { error in
                        fail("Could not load translators: \(error)")
                        doneAction()
                    })
                    .disposed(by: self.disposeBag)
            }
        }
    }

    private class func createController(dbConfig: Realm.Configuration) -> TranslatorsController {
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: URLSessionConfiguration.default)
        return TranslatorsController(apiClient: apiClient,
                                     indexStorage: RealmDbStorage(config: dbConfig),
                                     fileStorage: FileStorageController(),
                                     bundle: Bundle(for: TranslatorsControllerSpec.self))
    }

    private class func createVersion() -> String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        return "\(version)-iOS"
    }
}
