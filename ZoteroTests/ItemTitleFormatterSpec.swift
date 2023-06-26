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
    override class func spec() {
        describe("an item title formatter") {
            // Retain realm with inMemoryIdentifier so that data are not deleted
            var realm: Realm!
            var itemRawType: String!
            var itemBaseTitle: String!
            var creators: [(String, ItemDetailState.Creator.NamePresentation, Bool)]!
            var fields: [(String, String)]!
            var title: String!
            
            beforeSuite {
                let config = Realm.Configuration(inMemoryIdentifier: "TestsRealmConfig")
                realm = try! Realm(configuration: config)
            }
            
            beforeEach {
                try? realm.write {
                    realm.deleteAll()
                }
                realm.refresh()
                creators = []
                fields = []
            }
            
            justBeforeEach {
                let item = RItem()
                item.rawType = itemRawType
                item.baseTitle = itemBaseTitle
                createCreators(creators, in: item)
                createFields(fields, in: item)
                
                try? realm.write {
                    realm.add(item)
                }
                
                title = ItemTitleFormatter.displayTitle(for: item)
            }
            
            context("with a letter") {
                beforeEach {
                    itemRawType = "letter"
                }
                
                context("where baseTitle exists") {
                    beforeEach {
                        itemBaseTitle = "Some item title"
                        creators = [("recipient", .full, false)]
                    }
                    
                    it("title is same as baseTitle") {
                        expect(title).to(equal(itemBaseTitle))
                    }
                }
                
                context("where baseTitle is empty") {
                    beforeEach {
                        itemBaseTitle = ""
                    }
                    
                    context("with 0 creators") {
                        it("creates title with item type") {
                            expect(title).to(equal("[Letter]"))
                        }
                    }
                    
                    context("with 1 recipient and separate name presentation") {
                        beforeEach {
                            creators = [("recipient", .separate, false)]
                        }
                        
                        it("creates title with recipient last name") {
                            expect(title).to(equal("[Letter to Surname0]"))
                        }
                    }
                    
                    context("with 1 recipient and full name presentation") {
                        beforeEach {
                            creators = [("recipient", .full, false)]
                        }
                        
                        it("creates title with recipient full name") {
                            expect(title).to(equal("[Letter to Name0 Surname0]"))
                        }
                    }
                    
                    context("with 2 recipients and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("recipient", .separate, false), count: 2)
                        }
                        
                        it("creates title with recipient last names") {
                            expect(title).to(equal("[Letter to Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 2 recipients and mixed name presentation") {
                        beforeEach {
                            creators = [("recipient", .separate, false), ("recipient", .full, false)]
                        }
                        
                        it("creates title with recipient 1 full name and recipient 0 last name") {
                            expect(title).to(equal("[Letter to Name1 Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 3 recipients and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("recipient", .separate, false), count: 3)
                        }
                        
                        it("creates title with recipient last names") {
                            expect(title).to(equal("[Letter to Surname2, Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 4 or more recipients and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("recipient", .separate, false), count: .random(in: 4...15))
                        }
                        
                        it("creates title with last name et al") {
                            let count = creators.count
                            expect(title).to(equal("[Letter to Surname\(count - 1) et al.]"))
                        }
                    }
                    
                    context("with mixed creators and separate name presentation") {
                        beforeEach {
                            creators = [("author", .separate, false), ("contributor", .separate, false), ("recipient", .separate, false)]
                        }
                        
                        it("creates title with only recipient last name") {
                            expect(title).to(equal("[Letter to Surname2]"))
                        }
                    }
                }
            }
            
            context("with an interview") {
                beforeEach {
                    itemRawType = "interview"
                }
                
                context("where baseTitle exists") {
                    beforeEach {
                        itemBaseTitle = "Some item title"
                        creators = [("interviewer", .full, false)]
                    }
                    
                    it("title is same as baseTitle") {
                        expect(title).to(equal(itemBaseTitle))
                    }
                }
                
                context("where baseTitle is empty") {
                    beforeEach {
                        itemBaseTitle = ""
                    }
                    
                    context("with 0 creators") {
                        it("creates title with item type") {
                            expect(title).to(equal("[Interview]"))
                        }
                    }
                    
                    context("with 1 interviewer and separate name presentation") {
                        beforeEach {
                            creators = [("interviewer", .separate, false)]
                        }
                        
                        it("creates title with interviewer last name") {
                            expect(title).to(equal("[Interview by Surname0]"))
                        }
                    }
                    
                    context("with 1 interviewer and full name presentation") {
                        beforeEach {
                            creators = [("interviewer", .full, false)]
                        }
                        
                        it("creates title with interviewer full name") {
                            expect(title).to(equal("[Interview by Name0 Surname0]"))
                        }
                    }
                    
                    context("with 2 interviewers and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("interviewer", .separate, false), count: 2)
                        }
                        
                        it("creates title with interviewer last names") {
                            expect(title).to(equal("[Interview by Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 2 interviewers and mixed name presentation") {
                        beforeEach {
                            creators = [("interviewer", .separate, false), ("interviewer", .full, false)]
                        }
                        
                        it("creates title with interviewer 1 full name and interviewer 0 last name") {
                            expect(title).to(equal("[Interview by Name1 Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 3 interviewers and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("interviewer", .separate, false), count: 3)
                        }
                        
                        it("creates title with interviewer last names") {
                            expect(title).to(equal("[Interview by Surname2, Surname1 and Surname0]"))
                        }
                    }
                    
                    context("with 4 or more interviewers and separate name presentation") {
                        beforeEach {
                            creators = .init(repeating: ("interviewer", .separate, false), count: .random(in: 4...15))
                        }
                        
                        it("creates title with last name et al") {
                            let count = creators.count
                            expect(title).to(equal("[Interview by Surname\(count - 1) et al.]"))
                        }
                    }
                    
                    context("with mixed creators and separate name presentation") {
                        beforeEach {
                            creators = [("interviewee", .separate, false), ("translator", .separate, false), ("interviewer", .separate, false)]
                        }
                        
                        it("creates title with only interviewer last name") {
                            expect(title).to(equal("[Interview by Surname2]"))
                        }
                    }
                }
            }
            
            context("with a case") {
                beforeEach {
                    itemRawType = "case"
                }
                
                context("where baseTitle exists") {
                    beforeEach {
                        itemBaseTitle = "Some case"
                    }
                    
                    context("with no other fields") {
                        it("title is same as baseTitle") {
                            expect(title).to(equal(itemBaseTitle))
                        }
                    }
                    
                    context("with reporter field") {
                        beforeEach {
                            fields = [("reporter", "Reporter")]
                        }
                        
                        it("title is derived from baseTitle and reporter") {
                            expect(title).to(equal(itemBaseTitle + " (Reporter)"))
                        }
                    }
                    
                    context("with court field") {
                        beforeEach {
                            fields = [("court", "Court")]
                        }
                        
                        it("title is derived from baseTitle and court") {
                            expect(title).to(equal(itemBaseTitle + " (Court)"))
                        }
                    }
                    
                    context("with reporter and court fields") {
                        beforeEach {
                            fields = [("reporter", "Reporter"), ("court", "Court")]
                        }
                        
                        it("title is derived from baseTitle and reporter") {
                            expect(title).to(equal(itemBaseTitle + " (Reporter)"))
                        }
                    }
                }
                
                context("where baseTitle is empty") {
                    beforeEach {
                        itemBaseTitle = ""
                    }
                    
                    context("with 0 creators and no fields ") {
                        it("creates empty title") {
                            expect(title).to(equal("[]"))
                        }
                    }
                    
                    context("with court field") {
                        beforeEach {
                            fields = [("court", "Court")]
                        }
                        
                        it("title is derived from court") {
                            expect(title).to(equal("[Court]"))
                        }
                    }

                    context("with date field") {
                        beforeEach {
                            fields = [("date", "2019-01-01")]
                        }
                        
                        it("title is derived from court") {
                            expect(title).to(equal("[2019-01-01]"))
                        }
                    }
                    
                    context("with 2 primary authors") {
                        beforeEach {
                            creators = .init(repeating: ("author", .separate, true), count: 2)
                        }
                        
                        it("title is derived from first primary author") {
                            expect(title).to(equal("[Surname1]"))
                        }
                    }
                    
                    context("with 1 primary author and court and date fields") {
                        beforeEach {
                            creators = [("author", .separate, true)]
                            fields = [("court", "Court"), ("date", "2019-01-01")]
                        }
                        
                        it("title is derived from court, date, and author") {
                            expect(title).to(equal("[Court, 2019-01-01, Surname0]"))
                        }
                    }
                }
            }
        }
    }
    
    private class func createCreators(_ creators: [(type: String, namePresentation: ItemDetailState.Creator.NamePresentation, isPrimary: Bool)], in item: RItem) {
        let count = creators.count
        for index in (0..<count) {
            let creator = RCreator()
            creator.rawType = creators[index].type
            creator.primary = creators[index].isPrimary
            switch creators[index].namePresentation {
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
    
    private class func createFields(_ fields: [(key: String, value: String)], in item: RItem) {
        for (key, value) in fields {
            let field = RItemField()
            field.key = key
            field.value = value
            item.fields.append(field)
        }
    }
}
