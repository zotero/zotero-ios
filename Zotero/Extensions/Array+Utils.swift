//
//  Array+Utils.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//
//  Taken from: https://www.hackingwithswift.com/example-code/language/how-to-split-an-array-into-chunks
//

import UIKit

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }

    /// Finds an insertion index for given element in array. The array has to be sorted! Implemented as binary search.
    /// - parameter element: Element to be found/inserted
    /// - parameter areInIncreasingOrder: sorting function to be used to compare elements in array.
    /// - returns: Insertion index into sorted array.
    func index(of element: Element, sortedBy areInIncreasingOrder: (Element, Element) -> Bool) -> Int {
        var (low, high) = (0, self.count - 1)
        while low <= high {
            switch (low + high) / 2 {
            case let mid where areInIncreasingOrder(element, self[mid]): high = mid - 1
            case let mid where areInIncreasingOrder(self[mid], element): low = mid + 1
            case let mid: return mid // element found at mid
            }
        }
        return low // element not found, should be inserted here
    }

    func orderedMenuChildrenBasedOnDevice() -> Array<Element> {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return self.reversed()
        default: return self
        }
    }
}
