//
//  Store.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class StoreSubscriptionToken {}

typealias StoreSubscriptionAction<State> = (State) -> Void

protocol Store: class {
    associatedtype Action
    associatedtype State: Equatable

    var updater: StoreStateUpdater<State> { get }
    var state: State { get }

    func handle(action: Action)
    func subscribe(action: @escaping StoreSubscriptionAction<State>) -> StoreSubscriptionToken
}

extension Store {
    var state: State { return self.updater.state }

    func subscribe(action: @escaping StoreSubscriptionAction<State>) -> StoreSubscriptionToken {
        let token = StoreSubscriptionToken()
        inMainThread {
            action(self.state)
        }
        self.updater.subscribe(object: token, to: action)
        return token
    }
}

typealias UpdaterStateUpdateAction<State> = (inout State) -> Void

class StoreStateUpdater<State: Equatable> {
    private class Subscription {
        private var action: ((State) -> Void)?
        private weak var subscriber: AnyObject?

        init(subscriber: AnyObject, action: @escaping (State) -> Void) {
            self.action = action
            self.subscriber = subscriber
        }

        func performAction(for state: State) {
            if self.subscriber == nil {
                self.action = nil
                return
            }

            self.action?(state)
        }
    }

    private let queue: DispatchQueue

    private var subscriptions: [Subscription]
    private var unsafeState: State
    var state: State {
        get {
            var safeState: State?

            self.queue.sync {
                safeState = self.unsafeState
            }

            if let state = safeState {
                return state
            }

            fatalError("state nil in StateUpdater getter")
        }
    }
    var stateCleanupAction: ((inout State) -> Void)?

    init(initialState: State) {
        self.subscriptions = []
        self.unsafeState = initialState
        self.queue = DispatchQueue(label: "org.zotero.StateUpdaterQueue",
                                   qos: .userInitiated,
                                   attributes: .concurrent)
    }

    func subscribe(object: AnyObject, to action: @escaping StoreSubscriptionAction<State>) {
        let subscription = Subscription(subscriber: object, action: action)
        self.queue.async(flags: .barrier) {
            self.subscriptions.append(subscription)
        }
    }

    func updateState(action: @escaping UpdaterStateUpdateAction<State>) {
        self.queue.async(flags: .barrier) { [weak self] in
            self?.unsafeUpdateState(action: action)
        }
    }

    private func unsafeUpdateState(action: @escaping UpdaterStateUpdateAction<State>) {
        var newState = self.unsafeState
        self.stateCleanupAction?(&newState)
        action(&newState)

        if newState != self.unsafeState {
            self.unsafeState = newState
            inMainThread {
                self.subscriptions.forEach({ $0.performAction(for: newState) })
            }
        }
    }
}
