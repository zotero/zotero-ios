//
//  TagsFlowLayout.swift
//  Zotero
//
//  Created by Michal Rentka on 14.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TagsFlowLayout: UICollectionViewFlowLayout {
    private let maxWidth: CGFloat

    init(maxWidth: CGFloat, minimumInteritemSpacing: CGFloat = 0, minimumLineSpacing: CGFloat = 0, sectionInset: UIEdgeInsets = .zero) {
        self.maxWidth = maxWidth

        super.init()

        self.minimumInteritemSpacing = minimumInteritemSpacing
        self.minimumLineSpacing = minimumLineSpacing
        self.sectionInset = sectionInset

        self.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        self.sectionInsetReference = SectionInsetReference.fromLayoutMargins
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let superArray = super.layoutAttributesForElements(in: rect),
              let attributes = NSArray(array: superArray, copyItems: true) as? [UICollectionViewLayoutAttributes] else {  return nil  }

        var leftMargin: CGFloat = self.sectionInset.left
        var maxY: CGFloat = -1.0

        for layoutAttribute in attributes {
            guard layoutAttribute.representedElementCategory == .cell else { break }

            if layoutAttribute.frame.minY >= maxY {
                leftMargin = self.sectionInset.left
            }

            layoutAttribute.frame.origin.x = leftMargin
            leftMargin += layoutAttribute.frame.width + self.minimumInteritemSpacing
            maxY = max(layoutAttribute.frame.maxY, maxY)
        }

        return attributes
    }

    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        return true
    }

    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection {
        return UIUserInterfaceLayoutDirection.leftToRight
    }
}
