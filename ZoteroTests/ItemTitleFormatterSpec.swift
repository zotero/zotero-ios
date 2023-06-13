//
//  ItemTitleFormatterSpec.swift
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

final class ItemTitleFormatterSpec: QuickSpec {
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

        describe("letter") {
            describe("baseTitle exists") {
                it("title is same as baseTitle") {
                    let item = RItem()
                    item.rawType = "letter"
                    item.baseTitle = "Some item title"

                    let creator = RCreator()
                    creator.rawType = "recipient"
                    creator.name = "Name Surname"
                    item.creators.append(creator)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some item title"))
                }
            }

            describe("baseTitle is empty") {
                it("creates derived title from 0 creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter]"))
                }

                it("creates derived title from 1 creator") {
                    let item = RItem()
                    item.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 1, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .full, count: 1, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Name0 Surname0]"))
                }

                it("creates derived title from 2 creators") {
                    let item = RItem()
                    item.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 2, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname1 and Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 1, in: item2)
                    let creator = item2.creators.first!
                    creator.orderId = 2
                    self.createCreators(type: "recipient", namePresentation: .full, count: 1, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Name0 Surname0 and Surname0]"))
                }

                it("creates derived title from 3 creators") {
                    let item = RItem()
                    item.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 3, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname2, Surname1 and Surname0]"))
                }

                it("creates derived title from 4 and more creators") {
                    let item = RItem()
                    item.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 4, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname3 et al.]"))

                    let item2 = RItem()
                    item2.rawType = "letter"
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 15, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Surname14 et al.]"))
                }

                it("creates derived title from creators and ignores non-recipient creators") {
                    let item = RItem()
                    item.rawType = "letter"
                    self.createCreators(type: "author", namePresentation: .separate, count: 1, in: item)
                    self.createCreators(type: "contributor", namePresentation: .separate, count: 1, in: item)
                    self.createCreators(type: "recipient", namePresentation: .separate, count: 1, in: item)
                    let recipient = item.creators.first(where: { $0.rawType == "recipient" })!
                    recipient.lastName = "Surname2"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname2]"))
                }
            }
        }

        describe("interview") {
            describe("baseTitle exists") {
                it("title is same as baseTitle") {
                    let item = RItem()
                    item.rawType = "interview"
                    item.baseTitle = "Some item title"

                    let creator = RCreator()
                    creator.rawType = "interviewer"
                    creator.name = "Name Surname"
                    item.creators.append(creator)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some item title"))
                }
            }

            describe("baseTitle is empty") {
                it("creates derived title from 0 creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview]"))
                }

                it("creates derived title from 1 creator") {
                    let item = RItem()
                    item.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 1, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .full, count: 1, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Name0 Surname0]"))
                }

                it("creates derived title from 2 creators") {
                    let item = RItem()
                    item.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 2, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname1 and Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 1, in: item2)
                    let creator = item2.creators.first!
                    creator.orderId = 2
                    self.createCreators(type: "interviewer", namePresentation: .full, count: 1, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Name0 Surname0 and Surname0]"))
                }

                it("creates derived title from 3 creators") {
                    let item = RItem()
                    item.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 3, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname2, Surname1 and Surname0]"))
                }

                it("creates derived title from 4 and more creators") {
                    let item = RItem()
                    item.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 4, in: item)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname3 et al.]"))

                    let item2 = RItem()
                    item2.rawType = "interview"
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 15, in: item2)

                    try? self.realm.write {
                        self.realm.add(item2)
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Surname14 et al.]"))
                }

                it("creates derived title from creators and ignores non-interviewer creators") {
                    let item = RItem()
                    item.rawType = "interview"
                    self.createCreators(type: "interviewee", namePresentation: .separate, count: 1, in: item)
                    self.createCreators(type: "translator", namePresentation: .separate, count: 1, in: item)
                    self.createCreators(type: "interviewer", namePresentation: .separate, count: 1, in: item)
                    let recipient = item.creators.first(where: { $0.rawType == "interviewer" })!
                    recipient.lastName = "Surname2"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname2]"))
                }
            }
        }

        describe("case") {
            describe("baseTitle exists") {
                it("doesn't change baseTitle when other fields are not available") {
                    let item = RItem()
                    item.baseTitle = "Some case"
                    item.rawType = "case"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some case"))
                }

                it("creates derived baseTitle and reporter") {
                    let item = RItem()
                    item.baseTitle = "Some case"
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "reporter"
                    field.value = "Reporter"
                    item.fields.append(field)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some case (Reporter)"))
                }

                it("creates derived baseTitle and court") {
                    let item = RItem()
                    item.baseTitle = "Some case"
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "court"
                    field.value = "Court"
                    item.fields.append(field)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some case (Court)"))
                }

                it("creates derived baseTitle and reporter, ignores court when both available") {
                    let item = RItem()
                    item.baseTitle = "Some case"
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "reporter"
                    field.value = "Reporter"
                    item.fields.append(field)

                    let field2 = RItemField()
                    field2.key = "court"
                    field2.value = "Court"
                    item.fields.append(field2)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some case (Reporter)"))
                }
            }

            describe("baseTitle is empty") {
                it("shows [] if nothing is available") {
                    let item = RItem()
                    item.rawType = "case"

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[]"))
                }

                it("shows court if available") {
                    let item = RItem()
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "court"
                    field.value = "Court"
                    item.fields.append(field)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Court]"))
                }

                it("shows date if available") {
                    let item = RItem()
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "date"
                    field.value = "2019-01-01"
                    item.fields.append(field)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[2019-01-01]"))
                }

                it("shows first primary creator if available") {
                    let item = RItem()
                    item.rawType = "case"

                    let creator = RCreator()
                    creator.rawType = "author"
                    creator.primary = true
                    creator.firstName = "Name0"
                    creator.lastName = "Surname0"
                    creator.orderId = 1
                    item.creators.append(creator)

                    let creator2 = RCreator()
                    creator2.rawType = "author"
                    creator2.primary = true
                    creator2.firstName = "Name1"
                    creator2.lastName = "Surname1"
                    creator2.orderId = 0
                    item.creators.append(creator2)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Surname1]"))
                }

                it("shows court, date and creator if available") {
                    let item = RItem()
                    item.rawType = "case"

                    let field = RItemField()
                    field.key = "court"
                    field.value = "Court"
                    item.fields.append(field)

                    let field2 = RItemField()
                    field2.key = "date"
                    field2.value = "2019-01-01"
                    item.fields.append(field2)

                    let creator = RCreator()
                    creator.rawType = "author"
                    creator.primary = true
                    creator.firstName = "Name"
                    creator.lastName = "Surname"
                    creator.orderId = 0
                    item.creators.append(creator)

                    try? self.realm.write {
                        self.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Court, 2019-01-01, Surname]"))
                }
            }
        }
    }

    private func createCreators(type: String, namePresentation: ItemDetailState.Creator.NamePresentation, count: Int, in item: RItem) {
        for index in (0..<count) {
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
            item.creators.append(creator)
        }
    }
}
