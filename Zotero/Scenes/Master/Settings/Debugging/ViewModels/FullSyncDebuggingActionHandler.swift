//
//  FullSyncDebuggingActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 26.03.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

struct FullSyncDebuggingActionHandler: ViewModelActionHandler {
    typealias Action = FullSyncDebuggingAction
    typealias State = FullSyncDebuggingState

    private unowned let fullSyncDebugger: FullSyncDebugger
    private let disposeBag: DisposeBag

    init(fullSyncDebugger: FullSyncDebugger) {
        self.fullSyncDebugger = fullSyncDebugger
        disposeBag = DisposeBag()
    }

    func process(action: FullSyncDebuggingAction, in viewModel: ViewModel<FullSyncDebuggingActionHandler>) {
        switch action {
        case .start:
            start(viewModel: viewModel)

        case .startObserving:
            startObserving(viewModel: viewModel)
        }
    }

    func start(viewModel: ViewModel<FullSyncDebuggingActionHandler>) {
        fullSyncDebugger.start()
    }

    func startObserving(viewModel: ViewModel<FullSyncDebuggingActionHandler>) {
        fullSyncDebugger.syncTypeInProgress
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak viewModel] type in
                guard let viewModel else { return }
                update(viewModel: viewModel) { state in
                    state.syncTypeInProgress = type
                }
            })
            .disposed(by: disposeBag)
    }
}
