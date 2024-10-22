//
//  TrashObject.swift
//  Zotero
//
//  Created by Michal Rentka on 21.10.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol TrashObject: AnyObject {
    var key: String { get }
    var libraryId: LibraryIdentifier? { get }
    var dateAdded: Date { get }
    var dateModified: Date { get }
    var date: Date? { get }
    var sortTitle: String { get }
    var sortType: String? { get }
    var creatorSummary: String? { get }
    var publisher: String? { get }
    var publicationTitle: String? { get }
    var year: Int? { get }
    var isMainAttachmentDownloaded: Bool { get }
}

extension RItem: TrashObject {
    var date: Date? {
        return parsedDate
    }
    
    var sortType: String? {
        return localizedType
    }
    
    var year: Int? {
        return parsedYear
    }
    
    var isMainAttachmentDownloaded: Bool {
        return fileDownloaded
    }
}

extension RCollection: TrashObject {
    var dateAdded: Date {
        return .distantPast
    }
    
    var date: Date? {
        return nil
    }
    
    var sortTitle: String {
        return name
    }
    
    var sortType: String? {
        return nil
    }
    
    var creatorSummary: String? {
        return nil
    }
    
    var publisher: String? {
        return nil
    }
    
    var publicationTitle: String? {
        return nil
    }
    
    var year: Int? {
        return nil
    }
    
    var isMainAttachmentDownloaded: Bool {
        return false
    }
}
