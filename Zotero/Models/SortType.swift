//
//  SortType.swift
//  Zotero
//
//  Created by Michal Rentka on 09/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol SortType {
    var descriptors: [RealmSwift.SortDescriptor] { get }
}
