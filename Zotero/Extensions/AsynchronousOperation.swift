//
//  AsynchronousOperation.swift
//  Zotero
//
//  Created by Michal Rentka on 08/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class AsynchronousOperation: Operation {
    private enum State: String {
        case ready = "isReady"
        case executing = "isExecuting"
        case finished = "isFinished"
    }

    private let stateQueue = DispatchQueue(label: "org.zotero.AsynchronousOperation.StateQueue", attributes: .concurrent)
    private var _state: State = .ready
    private var state: State {
        get {
            self.stateQueue.sync {
                return self._state
            }
        }

        set {
            let oldKeyPath = self.state.rawValue
            let newKeyPath = newValue.rawValue

            willChangeValue(forKey: oldKeyPath)
            willChangeValue(forKey: newKeyPath)
            self.stateQueue.sync(flags: .barrier) {
                self._state = newValue
            }
            didChangeValue(forKey: newKeyPath)
            didChangeValue(forKey: oldKeyPath)
        }
    }

    override var isAsynchronous: Bool {
        return true
    }

    override var isExecuting: Bool {
        return self.state == .executing
    }

    override var isFinished: Bool {
        return self.state == .finished
    }

    override func start() {
        guard !self.isCancelled else {
            self.state = .finished
            return
        }

        self.state = .ready
        self.main()
    }

    override func main() {
        guard !self.isCancelled else {
            self.state = .finished
            return
        }
        self.state = .executing
    }

    func finish() {
        guard self.state == .executing else { return }
        self.state = .finished
    }

    override func cancel() {
        super.cancel()
        self.finish()
    }
}
