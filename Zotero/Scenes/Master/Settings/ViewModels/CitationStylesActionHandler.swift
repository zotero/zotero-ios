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
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, bundledDataStorage: DbStorage, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.bundledDataStorage = bundledDataStorage
        self.fileStorage = fileStorage
        self.scheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.CitationStylesActionHandler")
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

    private func add(style remoteStyle: RemoteCitationStyle, in viewModel: ViewModel<CitationStylesActionHandler>) {
        // Check whether style already exists locally and set `installed` flag if it does.
        if (try? self.bundledDataStorage.createCoordinator().perform(request: InstallStyleDbRequest(identifier: remoteStyle.id))) ?? false { return }

        // If it doesn't, we need to download and process it.
        let style = CitationStyle(identifier: remoteStyle.id, title: remoteStyle.title, updated: remoteStyle.updated, href: remoteStyle.href, filename: remoteStyle.name)
        let file = Files.style(filename: remoteStyle.name)
        let request = FileRequest(data: .external(style.href), destination: file)

        self.apiClient.download(request: request)
                      .subscribe(on: self.scheduler)
                      .observe(on: self.scheduler)
                      .subscribe(with: viewModel, onError: { viewModel, error in
                          self.update(viewModel: viewModel) { state in
                              DDLogError("CitationStylesActionHandler: can't download style - \(error)")
                              state.error = .addition(name: style.title, error: error)
                          }
                      }, onCompleted: { viewModel in
                          self.process(downloadedStyle: style, file: file, isDependent: remoteStyle.dependent, in: viewModel)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func process(downloadedStyle: CitationStyle, file: File, isDependent: Bool, in viewModel: ViewModel<CitationStylesActionHandler>) {
        guard isDependent, let (_, dependencyHref) = self.loadStyle(from: file), let dependencyUrl = dependencyHref.flatMap({ URL(string: $0) }) else {
            self._add(style: downloadedStyle, dependency: nil, in: viewModel)
            return
        }

        let file = Files.style(filename: dependencyUrl.lastPathComponent)
        let request = FileRequest(data: .external(dependencyUrl), destination: file)

        self.apiClient.download(request: request)
                      .subscribe(on: self.scheduler)
                      .observe(on: self.scheduler)
                      .subscribe(with: viewModel, onError: { viewModel, error in
                          self.update(viewModel: viewModel) { state in
                              DDLogError("CitationStylesActionHandler: can't download style - \(error)")
                              state.error = .addition(name: downloadedStyle.title, error: error)
                          }
                      }, onCompleted: { viewModel in
                          guard let (dependency, _) = self.loadStyle(from: file) else {
                              self._add(style: downloadedStyle, dependency: nil, in: viewModel)
                              return
                          }
                          self._add(style: downloadedStyle, dependency: dependency, in: viewModel)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func loadStyle(from file: File) -> (CitationStyle, String?)? {
        guard let parser = XMLParser(contentsOf: file.createUrl()) else { return nil }

        let delegate = StyleParserDelegate(filename: file.name)
        parser.delegate = delegate

        if parser.parse(), let style = delegate.style {
            return (style, delegate.dependencyHref)
        }
        return nil
    }

    private func _add(style: CitationStyle, dependency: CitationStyle?, in viewModel: ViewModel<CitationStylesActionHandler>) {
        do {
            try self.bundledDataStorage.createCoordinator().perform(request: StoreStyleDbRequest(style: style, dependency: dependency))

            self.update(viewModel: viewModel) { state in
                let index = state.styles.index(of: style, sortedBy: { $0.title.compare($1.title, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending })
                state.styles.insert(style, at: index)
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                DDLogError("CitationStylesActionHandler: can't store style - \(error)")
                state.error = .addition(name: style.title, error: error)
            }
        }
    }

    private func remove(at index: Int, in viewModel: ViewModel<CitationStylesActionHandler>) {
        guard index < viewModel.state.styles.count else { return }

        let style = viewModel.state.styles[index]

        do {
            let toRemove = try self.bundledDataStorage.createCoordinator().perform(request: UninstallStyleDbRequest(identifier: style.identifier))
            for identifier in toRemove {
                try? self.fileStorage.remove(Files.style(filename: identifier))
            }

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
            let styles = try self.bundledDataStorage.createCoordinator().perform(request: ReadInstalledStylesDbRequest()).compactMap({ style -> CitationStyle? in
                guard let href = URL(string: style.href) else { return nil }
                return CitationStyle(identifier: style.identifier, title: style.title, updated: style.updated, href: href, filename: style.filename)
            })

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
