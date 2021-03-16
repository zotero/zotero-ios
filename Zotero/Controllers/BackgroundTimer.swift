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
    private enum State {
        case suspended
        case resumed
    }

    private let timeInterval: DispatchTimeInterval
    private let queue: DispatchQueue

    var eventHandler: (() -> Void)?
    private var state: State = .suspended
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource(flags: [], queue: self.queue)
        t.schedule(deadline: .now() + self.timeInterval, repeating: 0)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
            self?.suspend()
        })
        return t
    }()

    init(timeInterval: DispatchTimeInterval, queue: DispatchQueue) {
        self.timeInterval = timeInterval
        self.queue = queue
    }

    deinit {
        self.timer.setEventHandler {}
        self.timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here https://forums.developer.apple.com/thread/15902
         */
        self.resume()
        self.eventHandler = nil
    }

    func resume() {
        guard self.state != .resumed else { return }
        self.state = .resumed
        self.timer.resume()
    }

    func suspend() {
        guard self.state != .suspended else { return }
        self.state = .suspended
        self.timer.suspend()
    }
}
