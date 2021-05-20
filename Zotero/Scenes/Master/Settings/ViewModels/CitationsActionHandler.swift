//
//  CitationsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct CitationsActionHandler: ViewModelActionHandler {
    typealias Action = CitationsAction
    typealias State = CitationsState

    private unowned let apiClient: ApiClient
    private unowned let bundledDataStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, bundledDataStorage: DbStorage, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.bundledDataStorage = bundledDataStorage
        self.fileStorage = fileStorage
        self.disposeBag = DisposeBag()
    }

    func process(action: CitationsAction, in viewModel: ViewModel<CitationsActionHandler>) {
        switch action {
        case .loadStyles:
            self.loadStyles(in: viewModel)

        case .loadRemoteStyles:
            self.loadRemoteStyles(in: viewModel)

        case .searchRemote(let string):
            self.filter(with: string, in: viewModel)

        case .addStyle(let style): break
        }
    }

    private func filter(with string: String, in viewModel: ViewModel<CitationsActionHandler>) {
        if string.isEmpty {
            self.update(viewModel: viewModel) { state in
                state.filteredRemoteStyles = nil
            }
        } else {
            self.update(viewModel: viewModel) { state in
                state.filteredRemoteStyles = state.remoteStyles.filter({ style in
                    return style.title.localizedCaseInsensitiveContains(string) || style.category.fields.contains(where: { $0.localizedCaseInsensitiveContains(string) })
                })
            }
        }
    }

    private func loadStyles(in viewModel: ViewModel<CitationsActionHandler>) {
        do {
            let styles = try self.bundledDataStorage.createCoordinator().perform(request: ReadStylesDbRequest())
            let token = styles.observe { [weak viewModel] change in
                switch change {
                case .update(let results, _, _, _):
                    guard let viewModel = viewModel else { return }
                    self.update(viewModel: viewModel) { state in
                        state.styles = results
                    }
                case .initial: break
                case .error: break
                }
            }

            self.update(viewModel: viewModel) { state in
                state.styles = styles
                state.stylesToken = token
            }
        } catch let error {
            // TODO: - Show error
        }
    }

    private func loadRemoteStyles(in viewModel: ViewModel<CitationsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.loadingRemoteStyles = true
        }

        self.apiClient.send(request: CitationStylesRequest())
            .observe(on: MainScheduler.instance)
            .subscribe(with: viewModel,
                       onSuccess: { (viewModel, response: (CitationStylesResponse, ResponseHeaders)) in
                           self.update(viewModel: viewModel) { state in
                               state.loadingRemoteStyles = false
                               state.remoteStyles = response.0.styles
                               state.loadingError = nil
                           }
                       }, onFailure: { viewModel, error in
                           self.update(viewModel: viewModel) { state in
                               state.loadingError = error
                               state.loadingRemoteStyles = false
                           }
                       })
                       .disposed(by: self.disposeBag)

    }
}
