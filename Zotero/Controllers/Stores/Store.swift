//
//  Store.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift
import RxCocoa

protocol Store: class {
    associatedtype Action
    associatedtype State: Equatable

    var updater: StoreStateUpdater<State> { get }
    var state: BehaviorRelay<State> { get }

    func handle(action: Action)
}

extension Store {
    var state: BehaviorRelay<State> { return self.updater.state }
}

typealias UpdaterStateUpdateAction<State> = (inout State) -> Void

class StoreStateUpdater<State: Equatable> {
    var state: BehaviorRelay<State>
    var stateCleanupAction: ((inout State) -> Void)?

    init(initialState: State) {
        self.state = BehaviorRelay(value: initialState)
    }

    func updateState(action: @escaping UpdaterStateUpdateAction<State>) {
        var newState = self.state.value
        self.stateCleanupAction?(&newState)
        action(&newState)

        if newState != self.state.value {
            self.state.accept(newState)
        }
    }
}
