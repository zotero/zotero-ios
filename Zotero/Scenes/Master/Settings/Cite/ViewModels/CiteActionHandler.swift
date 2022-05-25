//
//  CiteActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct CiteActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = CiteAction
    typealias State = CiteState

    private unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    let backgroundQueue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, bundledDataStorage: DbStorage, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.CitationStylesActionHandler.backgroundProcessing", qos: .userInitiated)
        self.apiClient = apiClient
        self.dbStorage = bundledDataStorage
        self.fileStorage = fileStorage
        self.backgroundQueue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.CitationStylesActionHandler.backgroundScheduler")
        self.disposeBag = DisposeBag()
    }

    func process(action: CiteAction, in viewModel: ViewModel<CiteActionHandler>) {
        switch action {
        case .load:
            self.loadStyles(in: viewModel)

        case .add(let style):
            self.installOrAdd(style: style, in: viewModel)

        case .remove(let index):
            self.remove(at: index, in: viewModel)
        }
    }

    private func installOrAdd(style: RemoteStyle, in viewModel: ViewModel<CiteActionHandler>) {
        self.perform(request: InstallStyleDbRequest(identifier: style.id), invalidateRealm: true) { [weak viewModel] result in
            guard let viewModel = viewModel else { return }

            switch result {
            case .success(let exists) where exists: return
            default: break
            }

            // If it doesn't exist, we need to download and process it.
            self.add(style: style, in: viewModel)
        }
    }

    private func add(style remoteStyle: RemoteStyle, in viewModel: ViewModel<CiteActionHandler>) {
        let file = Files.style(filename: remoteStyle.name)
        let request = FileRequest(url: remoteStyle.href, destination: file)

        self.apiClient.download(request: request, queue: self.backgroundQueue)
                      .subscribe(on: self.scheduler)
                      .observe(on: self.scheduler)
                      .subscribe(with: viewModel, onError: { viewModel, error in
                          DDLogError("CitationStylesActionHandler: can't download style - \(error)")
                          self.update(viewModel: viewModel) { state in
                              state.error = .addition(name: remoteStyle.title, error: error)
                          }
                      }, onCompleted: { viewModel in
                          if let style = self.loadStyle(from: file) {
                              self.process(style: style, in: viewModel)
                          } else {
                              DDLogError("CitationStylesActionHandler: can't parse downloaded style")
                              self.update(viewModel: viewModel) { state in
                                  state.error = .addition(name: remoteStyle.title, error: nil)
                              }
                              // Try removing unsuccessful download
                              try? self.fileStorage.remove(file)
                          }
                      })
                      .disposed(by: self.disposeBag)
    }

    private func process(style: Style, in viewModel: ViewModel<CiteActionHandler>) {
        guard let dependencyUrl = style.dependencyId.flatMap({ URL(string: $0) }) else {
            self._add(style: style, dependency: nil, in: viewModel)
            return
        }

        let file = Files.style(filename: dependencyUrl.lastPathComponent)
        let request = FileRequest(url: dependencyUrl, destination: file)

        self.apiClient.download(request: request, queue: self.backgroundQueue)
                      .subscribe(on: self.scheduler)
                      .observe(on: self.scheduler)
                      .subscribe(with: viewModel, onError: { viewModel, error in
                          self.update(viewModel: viewModel) { state in
                              DDLogError("CitationStylesActionHandler: can't download style - \(error)")
                              state.error = .addition(name: style.title, error: error)
                          }
                      }, onCompleted: { viewModel in
                          guard let dependency = self.loadStyle(from: file) else {
                              self._add(style: style, dependency: nil, in: viewModel)
                              return
                          }
                          self._add(style: style, dependency: dependency, in: viewModel)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func loadStyle(from file: File) -> Style? {
        guard let parser = XMLParser(contentsOf: file.createUrl()) else { return nil }

        let delegate = StyleParserDelegate(filename: file.name)
        parser.delegate = delegate

        if parser.parse(), let style = delegate.style {
            return style
        }
        return nil
    }

    private func _add(style: Style, dependency: Style?, in viewModel: ViewModel<CiteActionHandler>) {
        do {
            try self.dbStorage.perform(request: StoreStyleDbRequest(style: style, dependency: dependency), on: self.backgroundQueue)

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

    private func remove(at index: Int, in viewModel: ViewModel<CiteActionHandler>) {
        guard index < viewModel.state.styles.count else { return }

        let style = viewModel.state.styles[index]

        self.remove(style: style) { error in
            if let error = error {
                DDLogError("CiteActionHandler: can't delete style \(style.id) - \(error)")

                self.update(viewModel: viewModel) { state in
                    state.error = .deletion(name: style.title, error: error)
                }
                return
            }

            self.update(viewModel: viewModel) { state in
                if let index = state.styles.firstIndex(where: { $0.identifier == style.identifier }) {
                    state.styles.remove(at: index)
                }
            }
        }
    }

    private func remove(style: Style, completion: @escaping (Error?) -> Void) {
        self.backgroundQueue.async {
            do {
                try self._remove(style: style)

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

    private func _remove(style: Style) throws {
        var toRemove: [String] = []

        try self.dbStorage.perform(on: self.backgroundQueue, with: { coordinator in
            toRemove = try coordinator.perform(request: UninstallStyleDbRequest(identifier: style.identifier))

            self.resetDefaultStylesIfNeeded(removedStyle: style, coordinator: coordinator)

            coordinator.invalidate()
        })

        for identifier in toRemove {
            try? self.fileStorage.remove(Files.style(filename: identifier))
        }
    }

    private func resetDefaultStylesIfNeeded(removedStyle style: Style, coordinator: DbCoordinator) {
        let quickCopyRemoved = style.identifier == Defaults.shared.quickCopyStyleId
        let exportRemoved = style.identifier == Defaults.shared.exportStyleId

        guard quickCopyRemoved || exportRemoved else { return }

        let resetRemoved: (String) -> Void = { newId in
            if quickCopyRemoved {
                Defaults.shared.quickCopyStyleId = newId
            }
            if exportRemoved {
                Defaults.shared.exportStyleId = newId
            }
        }

        if let defaultStyle = try? coordinator.perform(request: ReadStyleDbRequest(identifier: "http://www.zotero.org/styles/chicago-note-bibliography")) {
            resetRemoved(defaultStyle.identifier)
        } else if let availableStyle = try? coordinator.perform(request: ReadStylesDbRequest()).first {
            resetRemoved(availableStyle.identifier)
        } else {
            resetRemoved("")
        }
    }

    private func loadStyles(in viewModel: ViewModel<CiteActionHandler>) {
        do {
            let rStyles = try self.dbStorage.perform(request: ReadInstalledStylesDbRequest(), on: .main)
            let styles = Array(rStyles.compactMap(Style.init))

            self.update(viewModel: viewModel) { state in
                state.styles = styles
            }
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = .loading(error)
            }
        }
    }
}
