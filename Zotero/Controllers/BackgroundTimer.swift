//
//  BackgroundTimer.swift
//  Zotero
//
//  Created by Michal Rentka on 02.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//
//  https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9
//

import Foundation

final class BackgroundTimer {
    enum State {
        case suspended
        case resumed
    }

    private let timeInterval: DispatchTimeInterval
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private(set) var startTime: DispatchTime?

    var eventHandler: (() -> Void)?
    private(set) var state: State = .suspended

    init(timeInterval: DispatchTimeInterval, queue: DispatchQueue) {
        self.timeInterval = timeInterval
        self.queue = queue
    }

    deinit {
        guard let timer else { return }
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
    }

    func resume() {
        guard state != .resumed else { return }
        state = .resumed
        timer = timer ?? createTimer()
        
        timer?.resume()
    }

    func suspend() {
        guard let timer, state != .suspended else { return }
        state = .suspended
        timer.suspend()
    }

    private func createTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        let now = DispatchTime.now()
        startTime = now
        timer.schedule(deadline: now + timeInterval, repeating: 0)
        timer.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
            self?.suspend()
        })
        return timer
    }
}
