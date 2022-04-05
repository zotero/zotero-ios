//
//  LowPowerModeController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.04.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class LowPowerModeController {
    private let disposeBag: DisposeBag

    var lowPowerModeEnabled: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    var observable: PublishSubject<Bool>

    init() {
        self.disposeBag = DisposeBag()
        self.observable = PublishSubject()

        DDLogInfo("LowPowerModeController: low power mode enabled = \(self.lowPowerModeEnabled)")

        NotificationCenter.default.rx
                                  .notification(.NSProcessInfoPowerStateDidChange)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] _ in
                                      self?.stateChanged()
                                  })
                                  .disposed(by: self.disposeBag)
    }

    private func stateChanged() {
        DDLogInfo("LowPowerModeController: low power mode changed = \(self.lowPowerModeEnabled)")
        self.observable.on(.next(self.lowPowerModeEnabled))
    }
}
