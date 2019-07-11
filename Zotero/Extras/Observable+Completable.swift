//
//  Observable+Completable.swift
//  Zotero
//
//  Created by Michal Rentka on 11/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

extension PrimitiveSequence where Trait == SingleTrait {
    public func asCompletable() -> Completable {
        return Completable.create { observer in
            return self.subscribe(onSuccess: { _ in observer(.completed) },
                                  onError: { observer(.error($0)) })
        }
    }
}
