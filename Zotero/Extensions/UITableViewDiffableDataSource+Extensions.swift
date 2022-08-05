//
//  UITableViewDiffableDataSource+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 28.04.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UITableViewDiffableDataSource {
    func section(for section: Int) -> SectionIdentifierType? {
        if #available(iOS 15.0, *) {
            return self.sectionIdentifier(for: section)
        } else {
            let snapshot = self.snapshot()
            if section < snapshot.sectionIdentifiers.count {
                return snapshot.sectionIdentifiers[section]
            }
            return nil
        }
    }

    func sectionIndex(for section: SectionIdentifierType) -> Int? {
        if #available(iOS 15.0, *) {
            return self.index(for: section)
        } else {
            let snapshot = self.snapshot()
            if let index = snapshot.sectionIdentifiers.firstIndex(of: section) {
                return index
            }
            return nil
        }
    }
}

extension UICollectionViewDiffableDataSource {
    func section(for section: Int) -> SectionIdentifierType? {
        if #available(iOS 15.0, *) {
            return self.sectionIdentifier(for: section)
        } else {
            let snapshot = self.snapshot()
            if section < snapshot.sectionIdentifiers.count {
                return snapshot.sectionIdentifiers[section]
            }
            return nil
        }
    }

    func sectionIndex(for section: SectionIdentifierType) -> Int? {
        if #available(iOS 15.0, *) {
            return self.index(for: section)
        } else {
            let snapshot = self.snapshot()
            if let index = snapshot.sectionIdentifiers.firstIndex(of: section) {
                return index
            }
            return nil
        }
    }
}
