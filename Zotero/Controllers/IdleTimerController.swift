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
    private static let customIdleTimerTimeout: DispatchTimeInterval = .seconds(300)
    private let disposeBag: DisposeBag
    /// Processes which require idle timer disabled
    private var activeProcesses: Int = 0
    private var activeTimer: DispatchSourceTimer?

    init() {
        disposeBag = DisposeBag()
        observeOrientationChange()
        observeLowPowerMode()

        func observeOrientationChange() {
            NotificationCenter.default.rx
                .notification(UIDevice.orientationDidChangeNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    self?.resetCustomTimer()
                })
                .disposed(by: disposeBag)
        }

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
            activeTimer.suspend()
            activeTimer.schedule(deadline: .now() + Self.customIdleTimerTimeout)
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
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        func startTimer(controller: IdleTimerController) {
            let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
            timer.schedule(deadline: .now() + Self.customIdleTimerTimeout)
            timer.setEventHandler(handler: { [weak controller] in
                controller?.forceStopIdleTimer()
            })
            timer.resume()
            controller.activeTimer = timer
        }
    }

    func stopCustomIdleTimer() {
        inMainThread { [weak self] in
            guard let self else { return }

            if activeProcesses > 0 {
                activeProcesses -= 1
                DDLogInfo("IdleTimerController: enable idle timer \(activeProcesses)")
            } else {
                DDLogWarn("IdleTimerController: tried to enable idle timer with no active processes")
                activeProcesses = 0
            }

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
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private func set(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func forceStopIdleTimer() {
        DDLogInfo("IdleTimerController: force stop timer")
        activeProcesses = 1
        stopCustomIdleTimer()
    }
}
