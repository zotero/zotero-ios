//
//  OpenItemsController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 20/9/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import RxSwift

import CocoaLumberjackSwift

final class OpenItemsController {
    // MARK: Types
    enum Item: Hashable, Equatable {
        case pdf(library: Library, key: String, url: URL)
    }
    
    // MARK: Properties
    private(set) var items: [Item] = []
    let observable: PublishSubject<[Item]>
    private let disposeBag: DisposeBag
    
    // MARK: Object Lifecycle
    init() {
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
    }
    
    // MARK: Actions
    func open(_ item: Item) {
        // TODO: Use a better data structure, such as an ordered set
        // TODO: Keep track of last opened item
        guard !items.contains(where: { $0 == item }) else { return }
        items.append(item)
        DDLogInfo("OpenItemsController: opened \(item)")
        observable.on(.next(items))
    }
}
