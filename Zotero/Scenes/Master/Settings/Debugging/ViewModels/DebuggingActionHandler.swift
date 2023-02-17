//
//  DebuggingActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

struct DebuggingActionHandler: ViewModelActionHandler {
    typealias Action = DebuggingAction
    typealias State = DebuggingState

    private unowned let debugLogging: DebugLogging
    private unowned let coordinatorDelegate: DebuggingSettingsSettingsCoordinatorDelegate

    init(debugLogging: DebugLogging, coordinatorDelegate: DebuggingSettingsSettingsCoordinatorDelegate) {
        self.debugLogging = debugLogging
        self.coordinatorDelegate = coordinatorDelegate
    }

    func process(action: DebuggingAction, in viewModel: ViewModel<DebuggingActionHandler>) {
        switch action {
        case .startImmediateLogging:
            self.debugLogging.start(type: .immediate)
            self.monitor(logLines: self.debugLogging.logLines, in: viewModel)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

        case .startLoggingOnNextLaunch:
            self.debugLogging.start(type: .nextLaunch)

        case .stopLogging:
            self.debugLogging.stop()
            self.update(viewModel: viewModel) { state in
                state.isLogging = false
                state.numberOfLines = 0
                state.disposeBag = nil
            }

        case .exportDb:
            self.coordinatorDelegate.exportDb()

        case .monitorIfNeeded:
            guard viewModel.state.isLogging else { return }
            self.monitor(logLines: self.debugLogging.logLines, in: viewModel)

        case .clearLogs:
            self.debugLogging.cancel {
                self.update(viewModel: viewModel) { state in
                    state.numberOfLines = 0
                }
                self.debugLogging.start(type: .immediate)
                self.monitor(logLines: self.debugLogging.logLines, in: viewModel)
            }

        case .showLogs:
            self.coordinatorDelegate.showLogs(string: self.debugLogging.logString)

        case .cancelLogging:
            self.debugLogging.cancel()
            self.update(viewModel: viewModel) { state in
                state.isLogging = false
                state.numberOfLines = 0
                state.disposeBag = nil
            }
        }
    }

    private func monitor(logLines: BehaviorRelay<Int>, in viewModel: ViewModel<DebuggingActionHandler>) {
        let disposeBag = DisposeBag()
        logLines.observe(on: MainScheduler.instance)
                .subscribe(with: viewModel, onNext: { viewModel, lines in
                    self.update(viewModel: viewModel) { state in
                        state.numberOfLines = lines
                    }
                })
                .disposed(by: disposeBag)
        self.update(viewModel: viewModel) { state in
            state.disposeBag = disposeBag
        }
    }
}
