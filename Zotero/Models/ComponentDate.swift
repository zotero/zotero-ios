//
//  ComponentDate.swift
//  Zotero
//
//  Created by Michal Rentka on 28/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ComponentDate: CustomStringConvertible, Equatable {
    let day: Int
    let month: Int
    let year: Int
    let order: String

    var date: Date? {
        guard self.year > 0 else { return nil }
        let components = DateComponents(year: self.year, month: max(1, self.month), day: max(1, self.day))
        return Calendar.current.date(from: components)
    }

    var description: String {
        return "\(self.day)-\(self.month)-\(self.year) \(self.order)"
    }
}
