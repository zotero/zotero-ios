//
//  ViewModel.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

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

final class ViewModel<Handler: ViewModelActionHandler>: ObservableObject {
    private let handler: Handler
    private let disposeBag: DisposeBag

    let objectWillChange: ObservableObjectPublisher

    private(set) var stateObservable: BehaviorRelay<Handler.State>
    var state: Handler.State {
        return self.stateObservable.value
    }

    init(initialState: Handler.State, handler: Handler) {
        self.handler = handler
        self.stateObservable = BehaviorRelay(value: initialState)
        self.objectWillChange = ObservableObjectPublisher()
        self.disposeBag = DisposeBag()
    }

    func process(action: Handler.Action) {
        self.handler.process(action: action, in: self)
    }

    func binding<Value>(keyPath: Swift.KeyPath<Handler.State, Value>, action: @escaping (Value) -> Handler.Action) -> Binding<Value> {
        return Binding(get: { [unowned self] in
            return self.state[keyPath: keyPath]
        }, set: { [unowned self] value in
            self.process(action: action(value))
        })
    }

    func binding<Value>(get: @escaping (Handler.State) -> Value, action: @escaping (Value) -> Handler.Action?) -> Binding<Value> {
        return Binding(get: { [unowned self] in
            return get(self.state)
        }, set: { [unowned self] value in
            if let action = action(value) {
                self.process(action: action)
            }
        })
    }

    fileprivate func update(action: (inout Handler.State) -> Void) {
        var state = self.state
        state.cleanup()
        action(&state)
        self.stateObservable.accept(state)
        self.objectWillChange.send()
    }
}
