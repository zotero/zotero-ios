//
//  CitationStylesActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct CitationStylesActionHandler: ViewModelActionHandler {
    typealias Action = CitationStylesAction
    typealias State = CitationStylesState

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

    func process(action: CitationStylesAction, in viewModel: ViewModel<CitationStylesActionHandler>) {
        switch action {
        case .load:
            self.loadStyles(in: viewModel)

        case .add(let style):
            self.add(style: style, in: viewModel)

        case .remove(let index):
            self.remove(at: index, in: viewModel)
        }
    }

    private func add(style: RemoteCitationStyle, in viewModel: ViewModel<CitationStylesActionHandler>) {
        let request = FileRequest(data: .external(style.href), destination: Files.style(filename: style.name))
        self.apiClient.download(request: request)
                      .subscribe(with: viewModel, onNext: { viewModel, _ in
                          self._add(remoteStyle: style, in: viewModel)
                      }, onError: { viewModel, error in
                          self.update(viewModel: viewModel) { state in
                              DDLogError("CitationStylesActionHandler: can't download style - \(error)")
                              state.error = .addition(name: style.title, error: error)
                          }
                      })
                      .disposed(by: self.disposeBag)
    }

    private func _add(remoteStyle: RemoteCitationStyle, in viewModel: ViewModel<CitationStylesActionHandler>) {
        do {
            try self.bundledDataStorage.createCoordinator().perform(request: StoreStyleDbRequest(style: remoteStyle))

            self.update(viewModel: viewModel) { state in
                let style = CitationStyle(identifier: remoteStyle.name, title: remoteStyle.title, updated: remoteStyle.updated, href: remoteStyle.href)
                let index = state.styles.index(of: style, sortedBy: { $0.title > $1.title })
                state.styles.insert(style, at: index)
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                DDLogError("CitationStylesActionHandler: can't store style - \(error)")
                state.error = .addition(name: remoteStyle.title, error: error)
            }
        }
    }

    private func remove(at index: Int, in viewModel: ViewModel<CitationStylesActionHandler>) {
        guard index < viewModel.state.styles.count else { return }

        let style = viewModel.state.styles[index]

        do {
            try self.bundledDataStorage.createCoordinator().perform(request: DeleteStyleDbRequest(identifier: style.identifier))
            try self.fileStorage.remove(Files.style(filename: style.identifier))

            self.update(viewModel: viewModel) { state in
                if let index = state.styles.firstIndex(where: { $0.identifier == style.identifier }) {
                    state.styles.remove(at: index)
                }
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = .deletion(name: style.title, error: error)
            }
        }
    }

    private func loadStyles(in viewModel: ViewModel<CitationStylesActionHandler>) {
        do {
            let styles = try self.bundledDataStorage.createCoordinator().perform(request: ReadStylesDbRequest())
                                 .map({ CitationStyle(identifier: $0.identifier, title: $0.title, updated: $0.updated, href: (URL(string: $0.href) ?? URL(fileURLWithPath: ""))) })

            self.update(viewModel: viewModel) { state in
                state.styles = Array(styles)
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = .loading(error)
            }
        }
    }
}
