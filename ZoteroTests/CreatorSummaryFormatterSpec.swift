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

class CreatorSummaryFormatterSpec: QuickSpec {
    private static let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
    private static let realm = try! Realm(configuration: realmConfig) // Retain realm with inMemoryIdentifier so that data are not deleted

    override func spec() {
        beforeEach {
            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.deleteAll()
            }
            CreatorSummaryFormatterSpec.realm.refresh()
        }

        it("creates summary for no creators") {
            let results = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(beNil())
        }

        it("creates summary for 1 creator") {
            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 1))
            }

            let results = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname0"))

            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.deleteAll()
                CreatorSummaryFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .full, count: 1))
            }

            let results2 = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary2 = CreatorSummaryFormatter.summary(for: results2)
            expect(summary2).to(equal("Name0 Surname0"))
        }

        it("creates summary for 2 creators") {
            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 2))
            }

            let results = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname1 and Surname0"))
        }

        it("creates summary for 3+ creators") {
            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 3))
            }

            let results = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary = CreatorSummaryFormatter.summary(for: results)
            expect(summary).to(equal("Surname2 et al."))

            try? CreatorSummaryFormatterSpec.realm.write {
                CreatorSummaryFormatterSpec.realm.deleteAll()
                CreatorSummaryFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .separate, count: 15))
            }

            let results2 = CreatorSummaryFormatterSpec.realm.objects(RCreator.self)
            let summary2 = CreatorSummaryFormatter.summary(for: results2)
            expect(summary2).to(equal("Surname14 et al."))
        }
    }

    private func createCreators(type: String, namePresentation: ItemDetailStore.State.Creator.NamePresentation, count: Int) -> [RCreator] {
        return (0..<count).map { index in
            let creator = RCreator()
            creator.rawType = type
            switch namePresentation {
            case .full:
                creator.name = "Name\(index) Surname\(index)"
            case .separate:
                creator.firstName = "Name\(index)"
                creator.lastName = "Surname\(index)"
            }
            creator.orderId = count - index
            return creator
        }
    }
}
