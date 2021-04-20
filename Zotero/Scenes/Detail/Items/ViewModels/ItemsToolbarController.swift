//
//  ItemsToolbarController.swift
//  Zotero
//
//  Created by Michal Rentka on 19.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ItemsToolbarController {
    private static let finishVisibilityTime: RxTimeInterval = .seconds(2)
    private unowned let viewController: UINavigationController
    private let disposeBag: DisposeBag

    private var pendingErrors: [Error]?

    init(parent: UINavigationController, progressObservable: PublishSubject<SyncProgress>) {
        self.viewController = parent
        self.disposeBag = DisposeBag()

        progressObservable.observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] progress in
                              guard let `self` = self else { return }
//                              self.update(progress: progress, in: self.viewController)
                          })
                          .disposed(by: self.disposeBag)
    }

}
