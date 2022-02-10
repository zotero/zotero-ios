//
//  DragDropController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class DragDropController {
    func dragItem(from item: RItem) -> UIDragItem {
        let provider = NSItemProvider(object: item.key as NSString)
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = item
        return dragItem
    }

    func item(from dragItem: UIDragItem) -> RItem? {
        return dragItem.localObject as? RItem
    }

    func itemKeys(from dragItems: [UIDragItem], completed: @escaping ([String]) -> Void) {
        var keys: [String] = []

        let group = DispatchGroup()

        for dragItem in dragItems {
            group.enter()

            dragItem.itemProvider.loadObject(ofClass: NSString.self) { nsString, error in
                if let key = nsString as? String {
                    keys.append(key)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completed(keys)
        }
    }
}
