//
//  CreatorSummaryFormatterSpec.swift
//  ZoteroTests
//
//  Created by Michal Rentka on 07/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import Foundation

import Nimble
import RealmSwift
import Quick

final class CreatorSummaryFormatterSpec: QuickSpec {
    override class func spec() {
        describe("a creator summary formatter") {
            var realm: Realm!
            var namePresentation: ItemDetailState.Creator.NamePresentation!
            var count: Int!
            var summary: String!
            
            beforeSuite {
                // Retain realm with inMemoryIdentifier so that data are not deleted
                let config = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
                realm = try! Realm(configuration: config)
            }
            
            beforeEach {
                try? realm.write {
                    realm.deleteAll()
                }
                realm.refresh()
            }
            
            justBeforeEach {
                try? realm.write {
                    realm.add(createCreators(type: "author", namePresentation: namePresentation, count: count))
                }
                let results = realm.objects(RItem.self).first!.creators
                summary = CreatorSummaryFormatter.summary(for: results)
            }
            
            context("with separate name presentation") {
                beforeEach {
                    namePresentation = .separate
                }
                
                context("with no creators") {
                    beforeEach {
                        count = 0
                    }
                    
                    it("creates a nil summary") {
                        expect(summary).to(beNil())
                    }
                }
                
                context("with 1 creator") {
                    beforeEach {
                        count = 1
                    }
                    
                    it("creates a last name summary") {
                        expect(summary).to(equal("Surname0"))
                    }
                }
                
                context("with 2 creators") {
                    beforeEach {
                        count = 2
                    }
                    
                    it("creates a 2 last names summary") {
                        expect(summary).to(equal("Surname1 and Surname0"))
                    }
                }
                
                context("with 3 or more creators") {
                    beforeEach {
                        count = .random(in: 3...15)
                    }
                    
                    it("creates a last name et al summary") {
                        expect(summary).to(equal("Surname\(count - 1) et al."))
                    }
                }
            }
            
            context("with full name presentation") {
                beforeEach {
                    namePresentation = .full
                }
                
                context("with no creators") {
                    beforeEach {
                        count = 0
                    }
                    
                    it("creates a nil summary") {
                        expect(summary).to(beNil())
                    }
                }
                
                context("with 1 creator") {
                    beforeEach {
                        count = 1
                    }
                    
                    it("creates a full name summary") {
                        expect(summary).to(equal("Name0 Surname0"))
                    }
                }
            }
        }
    }
    
    private class func createCreators(type: String, namePresentation: ItemDetailState.Creator.NamePresentation, count: Int) -> RItem {
        let list: List<RCreator> = List()
        for index in (0..<count) {
            let creator = RCreator()
            creator.uuid = UUID().uuidString
            creator.rawType = type
            creator.primary = true
            switch namePresentation {
            case .full:
                creator.name = "Name\(index) Surname\(index)"
            case .separate:
                creator.firstName = "Name\(index)"
                creator.lastName = "Surname\(index)"
            }
            creator.orderId = count - index
            list.append(creator)
        }

        let item = RItem()
        item.key = "AAAAAA"
        item.creators = list
        return item
    }
}
