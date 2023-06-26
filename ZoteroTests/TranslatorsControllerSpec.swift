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

final class TranslatorsControllerSpec: QuickSpec {
    override class func spec() {
        describe("a translators controller") {
            let baseUrl = URL(string: ApiConstants.baseUrlString)!
            let version = TranslatorsControllerSpec.createVersion()
            let bundledTimestamp = 1585834479
            let translatorId = "bbf1617b-d836-4665-9aae-45f223264460"
            let translatorUrl = "https://acontracorriente.chass.ncsu.edu/index.php/acontracorriente/article/view/1956"
            let bundledTranslatorTimestamp = 1471553464 // 2016-08-18 20:51:04
            let remoteTranslatorTimestamp = 1586188800 // 2020-04-06 16:00:00
            let remoteTimestamp = 1586182261 // 2020-04-06 16:00:00
            // We need to retain realm with memory identifier so that data are not deleted
            var realm: Realm!
            var dbStorage: DbStorage!
            var controller: TranslatorsAndStylesController!
            var disposeBag: DisposeBag!
            
            beforeEach {
                let config = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
                dbStorage = RealmDbStorage(config: config)
                realm = try! Realm(configuration: config)
                controller = TranslatorsControllerSpec.createController(apiClient: TestControllers.apiClient, bundledDataStorage: dbStorage, fileStorage: TestControllers.fileStorage)
                disposeBag = DisposeBag()
                
                try? TestControllers.fileStorage.remove(Files.translators)
                HTTPStubs.removeAllStubs()
            }
            
            it("Loads bundled data") {
                // Stub to "disable" remote request
                let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.initial.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Setup as first-time update
                controller.setupTest(timestamp: 0, hash: "", deleted: 0)
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            expect(controller.lastUpdate.timeIntervalSince1970).to(equal(Double(bundledTimestamp)))
                            
                            realm.refresh()
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(translator).toNot(beNil())
                            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp))))
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beTrue())
                            
                            controller.translators(matching: translatorUrl)
                                .observe(on: MainScheduler.instance)
                                .subscribe(onSuccess: { translators in
                                    expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                                    doneAction()
                                }, onFailure: { error in
                                    fail("Could not load translators: \(error)")
                                    doneAction()
                                })
                                .disposed(by: disposeBag)
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Updates existing outdated data with newer bundled data") {
                // Stub to "disable" remote request
                let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.startup.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Create local records
                controller.setupTest(timestamp: bundledTimestamp - 100, hash: "123abc", deleted: 0)
                
                try! realm.write {
                    let translator = RTranslatorMetadata()
                    translator.id = translatorId
                    translator.lastUpdated = Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp - 100))
                    realm.add(translator)
                }
                
                let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "Bundled/translators/translator", withExtension: "js")!
                try! TestControllers.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: translatorId))
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            expect(controller.lastUpdate.timeIntervalSince1970).to(equal(Double(bundledTimestamp)))
                            
                            realm.refresh()
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(translator).toNot(beNil())
                            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp))))
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beTrue())
                            
                            controller.translators(matching: translatorUrl)
                                .observe(on: MainScheduler.instance)
                                .subscribe(onSuccess: { translators in
                                    expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                                    doneAction()
                                }, onFailure: { error in
                                    fail("Could not load translators: \(error)")
                                    doneAction()
                                })
                                .disposed(by: disposeBag)
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Doesn't update newer existing data with outdated bundled data") {
                // Stub to "disable" remote request
                let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.startup.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Create local records
                controller.setupTest(timestamp: bundledTimestamp, hash: "123abc", deleted: 0)
                
                try! realm.write {
                    let translator = RTranslatorMetadata()
                    translator.id = translatorId
                    translator.lastUpdated = Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp + 100))
                    realm.add(translator)
                }
                
                let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "Bundled/translators/translator", withExtension: "js")!
                try! TestControllers.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: translatorId))
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            expect(controller.lastUpdate.timeIntervalSince1970).to(equal(Double(bundledTimestamp)))
                            
                            realm.refresh()
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(translator).toNot(beNil())
                            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp + 100))))
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beTrue())
                            
                            controller.translators(matching: translatorUrl)
                                .observe(on: MainScheduler.instance)
                                .subscribe(onSuccess: { translators in
                                    expect(translators.first?["browserSupport"] as? String).to(equal("gcsi"))
                                    doneAction()
                                }, onFailure: { error in
                                    fail("Could not load translators: \(error)")
                                    doneAction()
                                })
                                .disposed(by: disposeBag)
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Removes translator with bundle update") {
                // Stub to "disable" remote request
                let response = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xml><currentTime>\(bundledTimestamp)</currentTime><pdftools version=\"3.04\"/></xml>"
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.startup.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Create local records
                let deletedTranslatorId = "96b9f483-c44d-5784-cdad-ce21b984"
                
                controller.setupTest(timestamp: bundledTimestamp - 100, hash: "abc123", deleted: 0)
                
                try! realm.write {
                    let translator = RTranslatorMetadata()
                    translator.id = deletedTranslatorId
                    translator.lastUpdated = Date(timeIntervalSince1970: Double(remoteTranslatorTimestamp))
                    realm.add(translator)
                }
                
                let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "Bundled/translators/translator", withExtension: "js")!
                try! TestControllers.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: deletedTranslatorId))
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            realm.refresh()
                            
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", deletedTranslatorId).first
                            
                            expect(translator).to(beNil())
                            expect(TestControllers.fileStorage.has(Files.translator(filename: deletedTranslatorId))).to(beFalse())
                            
                            doneAction()
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Loads remote data") {
                // Stub to return remote translator
                let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators", withExtension: "xml")
                let response = try! String(contentsOf: responseUrl!)
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.initial.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Setup as first-time update
                controller.setupTest(timestamp: 0, hash: "", deleted: 0)
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            expect(controller.lastUpdate.timeIntervalSince1970).to(equal(Double(remoteTimestamp)))
                            
                            realm.refresh()
                            
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(translator).toNot(beNil())
                            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(remoteTranslatorTimestamp))))
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beTrue())
                            
                            controller.translators(matching: translatorUrl)
                                .observe(on: MainScheduler.instance)
                                .subscribe(onSuccess: { translators in
                                    expect(translators.first?["browserSupport"] as? String).to(equal("gcsi"))
                                    doneAction()
                                }, onFailure: { error in
                                    fail("Could not load translators: \(error)")
                                    doneAction()
                                })
                                .disposed(by: disposeBag)
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Removes translator with remote update") {
                // Stup to return remove translator with priority=0
                let responseUrl = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "translators_delete", withExtension: "xml")
                let response = try! String(contentsOf: responseUrl!)
                let request = RepoRequest(timestamp: bundledTimestamp, version: version, type: TranslatorsAndStylesController.UpdateType.initial.rawValue, styles: nil)
                createStub(for: request, ignoreBody: true, baseUrl: baseUrl, xmlResponse: response)
                
                // Setup as first-time update so that there is a bundle update as well
                controller.setupTest(timestamp: 0, hash: "", deleted: 0)
                
                // Perform update and wait for results
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.isLoading.skip(1).filter({ !$0 }).first()
                        .observe(on: MainScheduler.instance)
                        .subscribe(onSuccess: { _ in
                            realm.refresh()
                            
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(translator).to(beNil())
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beFalse())
                            
                            doneAction()
                        }, onFailure: { error in
                            fail("Could not finish loading: \(error)")
                            doneAction()
                        })
                        .disposed(by: disposeBag)
                    
                    controller.update()
                }
            }
            
            it("Resets to bundled data") {
                // Create local records
                controller.setupTest(timestamp: 1586185643, hash: "123abc", deleted: 0)
                
                try! realm.write {
                    let translator = RTranslatorMetadata()
                    translator.id = translatorId
                    translator.lastUpdated = Date(timeIntervalSince1970: Double(remoteTranslatorTimestamp))
                    realm.add(translator)
                }
                
                let translatorURL = Bundle(for: TranslatorsControllerSpec.self).url(forResource: "Bundled/translators/translator", withExtension: "js")!
                try! TestControllers.fileStorage.copy(from: Files.file(from: translatorURL), to: Files.translator(filename: translatorId))
                
                // Perform reset
                
                waitUntil(timeout: .seconds(10)) { doneAction in
                    controller.resetToBundle(completion: {
                        DispatchQueue.main.async {
                            // Check whether translator was reverted to bundled data
                            let translator = realm.objects(RTranslatorMetadata.self).filter("id = %@", translatorId).first
                            
                            expect(controller.lastUpdate.timeIntervalSince1970).to(equal(Double(bundledTimestamp)))
                            expect(translator).toNot(beNil())
                            expect(translator?.lastUpdated).to(equal(Date(timeIntervalSince1970: Double(bundledTranslatorTimestamp))))
                            expect(TestControllers.fileStorage.has(Files.translator(filename: translatorId))).to(beTrue())
                            
                            controller.translators(matching: translatorUrl)
                                .observe(on: MainScheduler.instance)
                                .subscribe(onSuccess: { translators in
                                    expect(translators.first?["browserSupport"] as? String).to(equal("gcsibv"))
                                    doneAction()
                                }, onFailure: { error in
                                    fail("Could not load translators: \(error)")
                                    doneAction()
                                })
                                .disposed(by: disposeBag)
                        }
                    })
                }
            }
        }
    }

    private class func createController(apiClient: ApiClient, bundledDataStorage: DbStorage, fileStorage: FileStorage) -> TranslatorsAndStylesController {
        return TranslatorsAndStylesController(apiClient: apiClient, bundledDataStorage: bundledDataStorage, fileStorage: fileStorage, bundle: Bundle(for: TranslatorsControllerSpec.self))
    }

    private class func createVersion() -> String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let bundle = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        return "\(version)-\(bundle)-iOS"
    }
}
