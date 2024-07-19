//
//  OrderedDictionary+Utils.swift
//  Zotero
//
//  Created by Michal Rentka on 19.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import OrderedCollections

extension OrderedDictionary {
    /// Finds an insertion index for given element in array. The array has to be sorted! Implemented as binary search.
    /// - parameter element: Element to be found/inserted
    /// - parameter areInIncreasingOrder: sorting function to be used to compare elements in array.
    /// - returns: Insertion index into sorted array.
    func index(of element: Value, sortedBy areInIncreasingOrder: (Value, Value) -> Bool) -> Int {
        var (low, high) = (0, self.count - 1)
        while low <= high {
            switch (low + high) / 2 {
            case let mid where areInIncreasingOrder(element, self.values[mid]): high = mid - 1
            case let mid where areInIncreasingOrder(self.values[mid], element): low = mid + 1
            case let mid: return mid // element found at mid
            }
        }
        return low // element not found, should be inserted here
    }
}
