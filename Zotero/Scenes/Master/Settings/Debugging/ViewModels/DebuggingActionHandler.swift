//
//  DebuggingActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class DebuggingActionHandler: ViewModelActionHandler {
    typealias Action = DebuggingAction
    typealias State = DebuggingState

    private unowned let debugLogging: DebugLogging
    private unowned let fileStorage: FileStorage
    private unowned let coordinatorDelegate: DebuggingSettingsSettingsCoordinatorDelegate

    init(debugLogging: DebugLogging, fileStorage: FileStorage, coordinatorDelegate: DebuggingSettingsSettingsCoordinatorDelegate) {
        self.debugLogging = debugLogging
        self.fileStorage = fileStorage
        self.coordinatorDelegate = coordinatorDelegate
    }

    func process(action: DebuggingAction, in viewModel: ViewModel<DebuggingActionHandler>) {
        switch action {
        case .startImmediateLogging:
            self.debugLogging.start(type: .immediate)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

            do {
                if let url: URL = try self.fileStorage.contentsOfDirectory(at: Files.debugLogDirectory).first {
                    try self.monitor(url: url, in: viewModel)
                } else {
                    // ?
                }
            } catch let error {
                DDLogError("DebuggingActionHandler: can't read logging file - \(error)")
            }

        case .startLoggingOnNextLaunch:
            self.debugLogging.start(type: .nextLaunch)

        case .stopLogging:
            self.debugLogging.stop()
            self.update(viewModel: viewModel) { state in
                state.isLogging = false
                state.numberOfLines = 0
                state.fileMonitor = nil
                state.disposeBag = nil
            }

        case .exportDb:
            self.coordinatorDelegate.exportDb()

        case .loadNumberOfLines:
            guard viewModel.state.isLogging else { return }

            do {
                if let url: URL = try self.fileStorage.contentsOfDirectory(at: Files.debugLogDirectory).first {
                    let numberOfLines = try self.readNumberOfLines(from: url)
                    self.update(viewModel: viewModel) { state in
                        state.numberOfLines = numberOfLines
                    }
                    try self.monitor(url: url, in: viewModel)
                } else {
                    // ?
                }
            } catch let error {
                DDLogError("DebuggingActionHandler: can't read logging file - \(error)")
            }
        }
    }

    private func readNumberOfLines(from url: URL) throws -> Int {
        let handler = try FileHandle(forReadingFrom: url)
        guard let string = try handler.readToEnd().flatMap({ String(data: $0, encoding: .utf8) }) else { return 0 }
        return string.components(separatedBy: .newlines).count
    }

    private func monitor(url: URL, in viewModel: ViewModel<DebuggingActionHandler>) throws {
        let disposeBag = DisposeBag()
        let monitor = try FileMonitor(url: url)

        monitor.observable
               .observe(on: MainScheduler.instance)
               .subscribe(with: self, onNext: { [weak viewModel] `self`, data in
                   guard let viewModel = viewModel, let string = String(data: data, encoding: .utf8) else { return }
                   self.update(viewModel: viewModel) { state in
                       state.numberOfLines += string.components(separatedBy: .newlines).count
                   }
               })
               .disposed(by: disposeBag)

        self.update(viewModel: viewModel) { state in
            state.disposeBag = disposeBag
            state.fileMonitor = monitor
        }
    }
}
