//
//  File.swift
//  Zotero
//
//  Created by Michal Rentka on 29.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import UIKit

import CocoaLumberjackSwift
import RxSwift

final class IdleTimerController {
    private static let customIdleTimerTimemout = 1200
    private let disposeBag: DisposeBag
    /// Processes which require idle timer disabled
    private var activeProcesses: Int = 0
    private var activeTimer: DispatchSourceTimer?

    init() {
        disposeBag = DisposeBag()
        observeLowPowerMode()

        func observeLowPowerMode() {
            NotificationCenter.default.rx
                .notification(.NSProcessInfoPowerStateDidChange)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard ProcessInfo.processInfo.isLowPowerModeEnabled, let self else { return }
                    forceStopIdleTimer()
                })
                .disposed(by: disposeBag)
        }
    }

    func resetCustomTimer() {
        inMainThread { [weak self] in
            guard let activeTimer = self?.activeTimer else { return }
            DDLogInfo("IdleTimerController: reset idle timer")
            activeTimer.suspend()
            activeTimer.schedule(deadline: .now() + DispatchTimeInterval.seconds(Self.customIdleTimerTimemout))
            activeTimer.resume()
        }
    }

    func startCustomIdleTimer() {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        inMainThread { [weak self] in
            guard let self else { return }
            activeProcesses += 1
            DDLogInfo("IdleTimerController: disable idle timer \(activeProcesses)")
            guard activeTimer == nil else { return }
            set(disabled: true)
            startTimer(controller: self)
        }

        func startTimer(controller: IdleTimerController) {
            let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
            timer.schedule(deadline: .now() + DispatchTimeInterval.seconds(Self.customIdleTimerTimemout))
            timer.setEventHandler(handler: { [weak controller] in
                controller?.forceStopIdleTimer()
            })
            timer.resume()
            controller.activeTimer = timer
        }
    }

    func stopCustomIdleTimer() {
        inMainThread { [weak self] in
            guard let self, activeProcesses > 0 else {
                DDLogWarn("IdleTimerController: tried to enable idle timer with no active processes")
                return
            }
            activeProcesses -= 1

            DDLogInfo("IdleTimerController: enable idle timer \(activeProcesses)")

            guard activeProcesses == 0 else { return }
            set(disabled: false)
            activeTimer?.suspend()
            activeTimer?.setEventHandler(handler: nil)
            activeTimer?.cancel()
            /*
             If the timer is suspended, calling cancel without resuming
             triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
             */
            activeTimer?.resume()
            activeTimer = nil
        }
    }

    private func set(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func forceStopIdleTimer() {
        DDLogInfo("IdleTimerController: force stop timer")
        activeProcesses = 0
        stopCustomIdleTimer()
    }
}
