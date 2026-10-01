//
//  LibrariesViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RxSwift

final class LibrariesViewController: UIViewController {
    private weak var collectionView: UICollectionView!

    private static let cellId = "LibraryCell"
    private static let headerId = "LibraryHeader"
    private static let customLibrariesSection = 0
    private static let groupLibrariesSection = 1
    private let viewModel: ViewModel<LibrariesActionHandler>
    private unowned let syncScheduler: SynchronizationScheduler
    private let disposeBag: DisposeBag

    private var refreshController: SyncRefreshController?
    weak var coordinatorDelegate: MasterLibrariesCoordinatorDelegate?
    private var isSplit: Bool {
        splitViewController?.isCollapsed == false
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<LibrariesActionHandler>, syncScheduler: SynchronizationScheduler) {
        self.viewModel = viewModel
        self.syncScheduler = syncScheduler
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupCollectionView()
        if #available(iOS 26.0, *) {
            registerForTraitChanges([UITraitSplitViewControllerLayoutEnvironment.self]) { (controller: LibrariesViewController, _: UITraitCollection) in
                controller.collectionView.collectionViewLayout.invalidateLayout()
                controller.collectionView.reloadData()
                controller.updateRefreshControl()
            }
        }
        viewModel.process(action: .loadData)
        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        func setupNavigationBar() {
            let primaryAction = UIAction(image: UIImage(systemName: "gear")) { [weak self] action in
                self?.coordinatorDelegate?.showSettings(sourceItem: action.sender as? UIPopoverPresentationControllerSourceItem)
            }
            let item = UIBarButtonItem(primaryAction: primaryAction)
            item.accessibilityLabel = L10n.Settings.title
            navigationItem.rightBarButtonItem = item
        }

        func setupCollectionView() {
            let collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
            collectionView.backgroundColor = .systemGroupedBackground
            collectionView.alwaysBounceVertical = true
            collectionView.dataSource = self
            collectionView.delegate = self
            collectionView.register(LibraryCell.self, forCellWithReuseIdentifier: Self.cellId)
            collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: Self.headerId)
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(collectionView)
            self.collectionView = collectionView

            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])

            func createLayout() -> UICollectionViewCompositionalLayout {
                return UICollectionViewCompositionalLayout { sectionIndex, environment in
                    let appearance: UICollectionLayoutListConfiguration.Appearance
                    if #available(iOS 26.0, *) {
                        appearance = environment.traitCollection.splitViewControllerLayoutEnvironment == .expanded ? .sidebar : .insetGrouped
                    } else {
                        appearance = .grouped
                    }
                    var configuration = UICollectionLayoutListConfiguration(appearance: appearance)
                    configuration.headerMode = sectionIndex == Self.groupLibrariesSection ? .supplementary : .none
                    if #available(iOS 26.0, *) {
                        if appearance == .insetGrouped {
                            configuration.separatorConfiguration.topSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 56, bottom: 0, trailing: 16)
                            configuration.separatorConfiguration.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: 56, bottom: 0, trailing: 16)
                        }
                    } else {
                        configuration.separatorConfiguration.color = .separator
                        configuration.separatorConfiguration.topSeparatorInsets.trailing = 0
                        configuration.separatorConfiguration.bottomSeparatorInsets.trailing = 0
                    }
                    return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                }
            }
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        updateRefreshControl()
    }

    private func updateRefreshControl() {
        if !isSplit {
            guard collectionView.refreshControl == nil else { return }
            refreshController = SyncRefreshController(libraryId: nil, view: collectionView, syncScheduler: syncScheduler)
        } else {
            refreshController = nil
        }
    }

    // MARK: - UI State

    private func update(to state: LibrariesState) {
        if state.changes.contains(.groups) {
            collectionView.reloadData()
        }

        if state.changes.contains(.groupDeletion) {
            showDefaultLibraryIfNeeded(for: state)
        }

        if let error = state.error {
            coordinatorDelegate?.show(error: error)
        }

        if let question = state.deleteGroupQuestion {
            coordinatorDelegate?.showDeleteGroupQuestion(id: question.id, name: question.name, viewModel: viewModel)
        }
    }

    // MARK: - Actions

    private func showDefaultLibraryIfNeeded(for state: LibrariesState) {
        switch coordinatorDelegate?.visibleLibraryId {
        case .none, .custom:
            break

        case .group(let groupId):
            if state.groupLibraries?.filter(.groupId(groupId)).first == nil {
                // Currently visible group was recently deleted, show default library
                coordinatorDelegate?.showDefaultLibrary()
            }
        }
    }
}

extension LibrariesViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        let groupCount = viewModel.state.groupLibraries?.count ?? 0
        return groupCount > 0 ? 2 : 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case Self.customLibrariesSection:
            return viewModel.state.customLibraries?.count ?? 0

        case Self.groupLibrariesSection:
            return viewModel.state.groupLibraries?.count ?? 0

        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Self.headerId, for: indexPath)
        if let header = header  as? UICollectionViewListCell {
            var configuration: UIListContentConfiguration
            if #available(iOS 26.0, *) {
                if traitCollection.splitViewControllerLayoutEnvironment == .expanded {
                    configuration = .sidebarHeader()
                } else {
                    configuration = .groupedHeader()
                }
            } else {
                configuration = .groupedHeader()
                configuration.axesPreservingSuperviewLayoutMargins = []
                configuration.directionalLayoutMargins.leading = 60
                configuration.directionalLayoutMargins.trailing = 16
            }
            configuration.text = L10n.Libraries.groupLibraries
            header.contentConfiguration = configuration
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.cellId, for: indexPath)
        if let cell = cell as? LibraryCell, let (name, state) = libraryData(for: indexPath) {
            cell.setup(with: name, libraryState: state)
        }
        return cell

        func libraryData(for indexPath: IndexPath) -> (name: String, state: LibraryCell.LibraryState)? {
            switch indexPath.section {
            case Self.customLibrariesSection:
                let library = viewModel.state.customLibraries?[indexPath.item]
                return library.flatMap({ ($0.type.libraryName, .normal) })

            case Self.groupLibrariesSection:
                guard let library = viewModel.state.groupLibraries?[indexPath.item] else { return nil }
                let state: LibraryCell.LibraryState
                if library.isLocalOnly {
                    state = .archived
                } else if !library.canEditMetadata {
                    state = .locked
                } else {
                    state = .normal
                }
                return (library.name, state)

            default:
                return nil
            }
        }
    }
}

extension LibrariesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let library = library(for: indexPath) {
            coordinatorDelegate?.showCollections(for: library.identifier)
        }

        func library(for indexPath: IndexPath) -> Library? {
            switch indexPath.section {
            case Self.customLibrariesSection:
                let library = viewModel.state.customLibraries?[indexPath.item]
                return library.flatMap({ Library(customLibrary: $0) })

            case Self.groupLibrariesSection:
                let library = viewModel.state.groupLibraries?[indexPath.item]
                return library.flatMap({ Library(group: $0) })

            default:
                return nil
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.section == Self.groupLibrariesSection, let group = viewModel.state.groupLibraries?[indexPath.item], group.isLocalOnly else { return nil }

        let groupId = group.identifier
        let groupName = group.name

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return createContextMenu(for: groupId, groupName: groupName)
        }

        func createContextMenu(for groupId: Int, groupName: String) -> UIMenu {
            let delete = UIAction(title: L10n.remove, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .showDeleteGroupQuestion((groupId, groupName)))
            }
            return UIMenu(title: "", children: [delete])
        }
    }
}

extension LibrariesViewController: BottomSheetObserver { }

extension LibrariesViewController: WebViewProvider {
    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let webView: WKWebView = configuration.flatMap({ WKWebView(frame: .zero, configuration: $0) }) ?? WKWebView()
        webView.isHidden = true
        view.insertSubview(webView, at: 0)
        return webView
    }
}
