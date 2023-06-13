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
    // Retain realm with inMemoryIdentifier so that data are not deleted
    private let realm: Realm

    required init() {
        let config = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
        self.realm = try! Realm(configuration: config)
    }

    override func spec() {
        beforeEach {
            try? self.realm.write {
                self.realm.deleteAll()
            }
            self.realm.refresh()
        }

        it("creates summary for no creators") {
            try? self.realm.write {
                self.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 0))
            }

            let results = self.realm.objects(RItem.self).first!.creators
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(beNil())
        }

        it("creates summary for 1 creator") {
            try? self.realm.write {
                self.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 1))
            }

            let results = self.realm.objects(RItem.self).first!.creators
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname0"))

            try? self.realm.write {
                self.realm.deleteAll()
                self.realm.add(self.createCreators(type: "author", namePresentation: .full, count: 1))
            }

            let results2 = self.realm.objects(RItem.self).first!.creators
            let summary2 = CreatorSummaryFormatter.summary(for: results2)
            expect(summary2).to(equal("Name0 Surname0"))
        }

        it("creates summary for 2 creators") {
            try? self.realm.write {
                self.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 2))
            }

            let results = self.realm.objects(RItem.self).first!.creators
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname1 and Surname0"))
        }

        it("creates summary for 3+ creators") {
            try? self.realm.write {
                self.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 3))
            }

            let results = self.realm.objects(RItem.self).first!.creators
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname2 et al."))

            try? self.realm.write {
                self.realm.deleteAll()
                self.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 15))
            }

            let results2 = self.realm.objects(RItem.self).first!.creators
            let summary2 = CreatorSummaryFormatter.summary(for: results2)
            expect(summary2).to(equal("Surname14 et al."))
        }
    }

    private func createCreators(type: String, namePresentation: ItemDetailState.Creator.NamePresentation, count: Int) -> RItem {
        let list: List<RCreator> = List()
        for index in (0..<count) {
            let creator = RCreator()
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
