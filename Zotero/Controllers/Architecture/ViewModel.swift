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
    func update(viewModel: ViewModel<Self>, notifyListeners: Bool = true, action: (inout State) -> Void) {
        viewModel.update(notifyListeners: notifyListeners, action: action)
    }
}

protocol BackgroundDbProcessingActionHandler {
    var backgroundQueue: DispatchQueue { get }
    var dbStorage: DbStorage { get }

    /// Performs database request in background.
    /// - parameter request: Database request to perform
    /// - parameter completion: Handler called after db request is performed. Contains error if any occured. Always called on main thread.
    func perform<Request: DbRequest>(request: Request, completion: @escaping (Error?) -> Void)

    /// Performs database request in background.
    /// - parameter request: Database request to perform.
    /// - parameter invalidateRealm: Indicates whether realm should be invalidated after use.
    /// - parameter completion: Handler called after db request is performed. Contains result with request response. Always called on main thread.
    func perform<Request: DbResponseRequest>(request: Request, invalidateRealm: Bool, completion: @escaping (Result<Request.Response, Error>) -> Void)
}

extension BackgroundDbProcessingActionHandler {
    func perform<Request: DbRequest>(request: Request, completion: @escaping (Error?) -> Void) {
        self.backgroundQueue.async {
            do {
                try self.dbStorage.perform(request: request, on: self.backgroundQueue)

                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    func perform(writeRequests: [DbRequest], completion: @escaping (Error?) -> Void) {
        self.backgroundQueue.async {
            do {
                try self.dbStorage.perform(writeRequests: writeRequests, on: self.backgroundQueue)

                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }

    func perform<Request: DbResponseRequest>(request: Request, invalidateRealm: Bool, completion: @escaping (Result<Request.Response, Error>) -> Void) {
        self.backgroundQueue.async {
            do {
                let result = try self.dbStorage.perform(request: request, on: self.backgroundQueue, invalidateRealm: invalidateRealm)

                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

final class ViewModel<Handler: ViewModelActionHandler>: ObservableObject {
    let handler: Handler
    private let disposeBag: DisposeBag

    let objectWillChange: ObservableObjectPublisher

    private(set) var stateObservable: PublishSubject<Handler.State>
    private(set) var state: Handler.State

    init(initialState: Handler.State, handler: Handler) {
        self.handler = handler
        self.state = initialState
        self.stateObservable = PublishSubject()
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

    fileprivate func update(notifyListeners: Bool, action: (inout Handler.State) -> Void) {
        var state = self.state
        state.cleanup()
        action(&state)
        self.state = state

        guard notifyListeners else { return }

        inMainThread {
            self.stateObservable.on(.next(state))
            self.objectWillChange.send()
        }
    }
}
