//
//  ReadAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        return database.objects(RItem.self).filter(.parent(self.attachmentKey, in: self.libraryId))
                                           .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
                                           .filter(.deleted(false))
                                           .filter("annotationType in %@", supportedTypes)
                                           .sorted(byKeyPath: "annotationSortIndex", ascending: true)
    }
}

struct ReadDefaultAnnotationPageLabelDbRequest: DbResponseRequest {
    typealias Response = DefaultAnnotationPageLabel
    
    let attachmentKey: String
    let libraryId: LibraryIdentifier
    
    var needsWrite: Bool { return false }
    
    func process(in database: Realm) throws -> DefaultAnnotationPageLabel {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        let annotations = database.objects(RItem.self)
            .filter(.parent(attachmentKey, in: libraryId))
            .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
            .filter(.deleted(false))
            .filter("annotationType in %@", supportedTypes)
        
        var uniquePageLabelsCountByPage: [Int: [String: Int]] = [:]
        for item in annotations {
            var rawPage: String?
            var pageLabel: String?
            for field in item.fields {
                switch field.key {
                case FieldKeys.Item.Annotation.Position.pageIndex:
                    rawPage = field.value
                    
                case FieldKeys.Item.Annotation.pageLabel:
                    pageLabel = field.value
                    
                default:
                    continue
                }
                if rawPage != nil && pageLabel != nil {
                    break
                }
            }
            
            guard let rawPage,
                  let page = Int(rawPage) ?? Double(rawPage).flatMap(Int.init),
                  let pageLabel,
                  !pageLabel.isEmpty,
                  pageLabel != "-"
            else { continue }
            
            var uniquePageLabelsCount = uniquePageLabelsCountByPage[page, default: [:]]
            uniquePageLabelsCount[pageLabel, default: 0] += 1
            uniquePageLabelsCountByPage[page] = uniquePageLabelsCount
        }
        
        var defaultPageLabelByPage: [Int: String] = [:]
        for (page, uniquePageLabelsCount) in uniquePageLabelsCountByPage {
            if let maxCount = uniquePageLabelsCount.values.max(),
               let defaultPageLabel = uniquePageLabelsCount.filter({ $0.value == maxCount }).keys.sorted().first {
                defaultPageLabelByPage[page] = defaultPageLabel
            }
        }
        
        let uniquePageOffsets = Set(defaultPageLabelByPage.map({ (page, pageLabel) in Int(pageLabel).flatMap({ $0 - page }) }))
        if uniquePageOffsets.count == 1, let uniquePageOffset = uniquePageOffsets.first, let commonPageOffset = uniquePageOffset {
            return .commonPageOffset(offset: commonPageOffset)
        }
        if !defaultPageLabelByPage.isEmpty {
            return .labelPerPage(labelsByPage: defaultPageLabelByPage)
        }
        return .commonPageOffset(offset: 1)
    }
}
