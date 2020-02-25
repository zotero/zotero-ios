//
//  ViewModel.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxCocoa
import RxSwift

protocol ViewModelState {
    mutating func cleanup()
}

protocol ViewModelActionHandler {
    associatedtype State: ViewModelState
    associatedtype Action

    func process(action: Action, in viewModel: ViewModel<Self>)
}

extension ViewModelActionHandler {
    func update(viewModel: ViewModel<Self>, action: (inout State) -> Void) {
        viewModel.update(action: action)
    }
}

class ViewModel<Handler: ViewModelActionHandler> {
    private let handler: Handler
    private let disposeBag: DisposeBag

    private(set) var stateObservable: BehaviorRelay<Handler.State>
    var state: Handler.State {
        return self.stateObservable.value
    }

    init(initialState: Handler.State, handler: Handler) {
        self.handler = handler
        self.stateObservable = BehaviorRelay(value: initialState)
        self.disposeBag = DisposeBag()
    }

    func process(action: Handler.Action) {
        self.handler.process(action: action, in: self)
    }

    fileprivate func update(action: (inout Handler.State) -> Void) {
        var state = self.state
        state.cleanup()
        action(&state)
        self.stateObservable.accept(state)
    }
}
