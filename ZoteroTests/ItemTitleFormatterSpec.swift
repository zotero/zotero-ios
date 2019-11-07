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

class ItemTitleFormatterSpec: QuickSpec {
    private static let realmConfig = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
    private static let realm = try! Realm(configuration: realmConfig) // Retain realm with inMemoryIdentifier so that data are not deleted

    override func spec() {
        beforeEach {
            try? ItemTitleFormatterSpec.realm.write {
                ItemTitleFormatterSpec.realm.deleteAll()
            }
            ItemTitleFormatterSpec.realm.refresh()
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
                    creator.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(creator)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some item title"))
                }
            }

            describe("baseTitle is empty") {
                it("creates derived title from 0 creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter]"))
                }

                it("creates derived title from 1 creator") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .separate,
                                                                             count: 1, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .full,
                                                                             count: 1, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Name0 Surname0]"))
                }

                it("creates derived title from 2 creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .separate,
                                                                             count: 2, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname1 and Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        let creator = self.createCreators(type: "recipient", namePresentation: .separate, count: 1, item: item2).first!
                        creator.orderId = 2
                        ItemTitleFormatterSpec.realm.add(creator)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .full,
                                                                             count: 1, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Name0 Surname0 and Surname0]"))
                }

                it("creates derived title from 3 creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .separate,
                                                                             count: 3, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname2, Surname1 and Surname0]"))
                }

                it("creates derived title from 4 and more creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .separate,
                                                                             count: 4, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Letter to Surname3 et al.]"))

                    let item2 = RItem()
                    item2.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "recipient", namePresentation: .separate,
                                                                             count: 15, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Letter to Surname14 et al.]"))
                }

                it("creates derived title from creators and ignores non-recipient creators") {
                    let item = RItem()
                    item.rawType = "letter"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "author", namePresentation: .separate,
                                                                             count: 1, item: item))
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "contributor", namePresentation: .separate,
                                                                             count: 1, item: item))
                        let recipient = self.createCreators(type: "recipient", namePresentation: .separate,
                                                            count: 1, item: item).first!
                        recipient.lastName = "Surname2"
                        ItemTitleFormatterSpec.realm.add(recipient)
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
                    creator.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(creator)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some item title"))
                }
            }

            describe("baseTitle is empty") {
                it("creates derived title from 0 creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview]"))
                }

                it("creates derived title from 1 creator") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .separate,
                                                                             count: 1, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .full,
                                                                             count: 1, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Name0 Surname0]"))
                }

                it("creates derived title from 2 creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .separate,
                                                                             count: 2, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname1 and Surname0]"))

                    let item2 = RItem()
                    item2.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        let creator = self.createCreators(type: "interviewer", namePresentation: .separate, count: 1, item: item2).first!
                        creator.orderId = 2
                        ItemTitleFormatterSpec.realm.add(creator)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .full,
                                                                             count: 1, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Name0 Surname0 and Surname0]"))
                }

                it("creates derived title from 3 creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .separate,
                                                                             count: 3, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname2, Surname1 and Surname0]"))
                }

                it("creates derived title from 4 and more creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .separate,
                                                                             count: 4, item: item))
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Interview by Surname3 et al.]"))

                    let item2 = RItem()
                    item2.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item2)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewer", namePresentation: .separate,
                                                                             count: 15, item: item2))
                    }

                    let title2 = ItemTitleFormatter.displayTitle(for: item2)
                    expect(title2).to(equal("[Interview by Surname14 et al.]"))
                }

                it("creates derived title from creators and ignores non-interviewer creators") {
                    let item = RItem()
                    item.rawType = "interview"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "interviewee", namePresentation: .separate,
                                                                             count: 1, item: item))
                        ItemTitleFormatterSpec.realm.add(self.createCreators(type: "translator", namePresentation: .separate,
                                                                             count: 1, item: item))
                        let recipient = self.createCreators(type: "interviewer", namePresentation: .separate,
                                                            count: 1, item: item).first!
                        recipient.lastName = "Surname2"
                        ItemTitleFormatterSpec.realm.add(recipient)
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

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
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
                    field.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
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
                    field.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
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
                    field.item = item

                    let field2 = RItemField()
                    field2.key = "court"
                    field2.value = "Court"
                    field2.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
                        ItemTitleFormatterSpec.realm.add(field2)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("Some case (Reporter)"))
                }
            }

            describe("baseTitle is empty") {
                it("shows [] if nothing is available") {
                    let item = RItem()
                    item.rawType = "case"

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
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
                    field.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
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
                    field.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
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
                    creator.item = item

                    let creator2 = RCreator()
                    creator2.rawType = "author"
                    creator2.primary = true
                    creator2.firstName = "Name1"
                    creator2.lastName = "Surname1"
                    creator2.orderId = 0
                    creator2.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(creator)
                        ItemTitleFormatterSpec.realm.add(creator2)
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
                    field.item = item

                    let field2 = RItemField()
                    field2.key = "date"
                    field2.value = "2019-01-01"
                    field2.item = item

                    let creator = RCreator()
                    creator.rawType = "author"
                    creator.primary = true
                    creator.firstName = "Name"
                    creator.lastName = "Surname"
                    creator.orderId = 0
                    creator.item = item

                    try? ItemTitleFormatterSpec.realm.write {
                        ItemTitleFormatterSpec.realm.add(item)
                        ItemTitleFormatterSpec.realm.add(field)
                        ItemTitleFormatterSpec.realm.add(field2)
                        ItemTitleFormatterSpec.realm.add(creator)
                    }

                    let title = ItemTitleFormatter.displayTitle(for: item)
                    expect(title).to(equal("[Court, 2019-01-01, Surname]"))
                }
            }
        }
    }

    private func createCreators(type: String, namePresentation: ItemDetailStore.State.Creator.NamePresentation, count: Int, item: RItem) -> [RCreator] {
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
            creator.item = item
            creator.orderId = count - index
            return creator
        }
    }
}
