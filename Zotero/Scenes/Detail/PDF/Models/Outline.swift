//
//  Outline.swift
//  Zotero
//
//  Created by Michal Rentka on 12.02.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

protocol Outline: Equatable, Hashable {
    var title: String { get }
    var children: [Self] { get }

    func contains(string: String) -> Bool
}

extension Outline {
    func childrenContain(string: String) -> Bool {
        for child in children {
            if child.contains(string: string) {
                return true
            }

            if child.childrenContain(string: string) {
                return true
            }
        }

        return false
    }
}

struct PDFOutline: Outline {
    let id: UUID
    let title: String
    let page: UInt
    let children: [PDFOutline]

    init(element: OutlineElement) {
        id = UUID()
        title = element.title ?? ""
        page = element.pageIndex
        children = (element.children ?? []).map(PDFOutline.init)
    }

    func contains(string: String) -> Bool {
        return title.localizedCaseInsensitiveContains(string) || UInt(string) == page
    }
}

struct HtmlEpubOutline: Outline {
    let id: UUID
    let title: String
    let location: [String: Any]
    let children: [HtmlEpubOutline]

    init(outline: HtmlEpubReaderState.Outline) {
        id = UUID()
        title = outline.title
        location = outline.location
        children = outline.children.map(HtmlEpubOutline.init)
    }

    static func == (lhs: HtmlEpubOutline, rhs: HtmlEpubOutline) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func contains(string: String) -> Bool {
        return title.localizedCaseInsensitiveContains(string)
    }
}
