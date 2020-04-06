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
import RxSwift
import RealmSwift
import Quick

class TranslatorsControllerSpec: QuickSpec {
    private let baseUrl = URL(string: ApiConstants.baseUrlString)!
    private let version = TranslatorsControllerSpec.createVersion()
    private let bundledTimestamp: Double = 1585834479
    private let fileStorage: FileStorageController = FileStorageController()
    private var dbConfig: Realm.Configuration!
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
            OHHTTPStubs.removeAllStubs()
        }

        it("Loads bundled data") {
            let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(self.bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(self.bundledTimestamp))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()
                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", "bbf1617b-d836-4665-9aae-45f223264460").first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: 1471546264)))
                        expect(self.fileStorage.has(Files.translator(filename: "bbf1617b-d836-4665-9aae-45f223264460"))).to(beTrue())

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

        it("Updates existing outdated data with bundled data") {

        }

        it("Doesn't update newer data with bundled data") {

        }

        it("Loads remote data") {
            let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators", withExtension: "xml")
            let response = try! String(contentsOf: responseUrl!)
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(1586182261))

                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()

                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", "bbf1617b-d836-4665-9aae-45f223264460").first

                        expect(translator).toNot(beNil())
                        expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: 1586181600)))
                        expect(self.fileStorage.has(Files.translator(filename: "bbf1617b-d836-4665-9aae-45f223264460"))).to(beTrue())

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

        it("Removes from remote update") {
            let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators_delete", withExtension: "xml")
            let response = try! String(contentsOf: responseUrl!)
            let request = TranslatorsRequest(timestamp: self.bundledTimestamp,
                                             version: self.version,
                                             type: TranslatorsController.UpdateType.initial.rawValue)
            createStub(for: request, baseUrl: self.baseUrl, xmlResponse: response)

            self.controller.setupTest(timestamp: 0, hash: "", deleted: 0)

            waitUntil(timeout: 10) { doneAction in
                self.controller.isLoading.skip(1).filter({ !$0 }).first()
                    .observeOn(MainScheduler.instance)
                    .subscribe(onSuccess: { _ in
                        let realm = try! Realm(configuration: self.dbConfig)
                        realm.refresh()

                        let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", "bbf1617b-d836-4665-9aae-45f223264460").first

                        expect(translator).to(beNil())
                        expect(self.fileStorage.has(Files.translator(filename: "bbf1617b-d836-4665-9aae-45f223264460"))).to(beFalse())

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
            self.controller.setupTest(timestamp: 1586185643, hash: "123abc", deleted: 0)

            try! self.realm.write {
                let translator = RTranslatorMetadata()
                translator.id = "bbf1617b-d836-4665-9aae-45f223264460"
                translator.lastUpdated = Date(timeIntervalSince1970: 1586181600)
            }

            self.controller.resetToBundle()

            expect(self.controller.lastUpdate.timeIntervalSince1970).to(equal(self.bundledTimestamp))

            let realm = try! Realm(configuration: self.dbConfig)
            realm.refresh()
            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", "bbf1617b-d836-4665-9aae-45f223264460").first

            expect(translator).toNot(beNil())
            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: 1471546264)))
            expect(self.fileStorage.has(Files.translator(filename: "bbf1617b-d836-4665-9aae-45f223264460"))).to(beTrue())
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
