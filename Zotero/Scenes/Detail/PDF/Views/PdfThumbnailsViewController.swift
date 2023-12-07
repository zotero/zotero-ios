//
//  PdfThumbnailsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class PdfThumbnailsViewController: UICollectionViewController {
    private static var cellId: String = "CellId"

    private let viewModel: ViewModel<PdfThumbnailsActionHandler>
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private lazy var cellRegistration: UICollectionView.CellRegistration<PdfThumbnailsCell, String> = {
        return UICollectionView.CellRegistration<PdfThumbnailsCell, String> { [weak self] cell, indexPath, label in
            let image = self?.viewModel.state.cache.object(forKey: NSNumber(value: indexPath.row))
            if image == nil {
                self?.viewModel.process(action: .load(UInt(indexPath.row)))
            }
            cell.contentConfiguration = PdfThumbnailsCell.ContentConfiguration(label: label, image: image)
        }
    }()

    init(viewModel: ViewModel<PdfThumbnailsActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()

        let layout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.contentInsets = PdfThumbnailsLayout.contentInsets
            return section
        }

        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray6
        setupCollectionView()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, state in
                self.update(state: state)
            })
            .disposed(by: disposeBag)

        func setupCollectionView() {
            let registration = cellRegistration
            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: { collectionView, indexPath, itemIdentifier in
                return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
            })
            collectionView.dataSource = dataSource
            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            collectionView.backgroundColor = .systemGray6
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        viewModel.process(action: .loadPages)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        self.viewModel.process(action: .setUserInterface(isDark: traitCollection.userInterfaceStyle == .dark))
    }

    func set(visiblePage: Int) {
        viewModel.process(action: .setSelectedPage(pageIndex: visiblePage, type: .fromDocument))
    }

    private func update(state: PdfThumbnailsState) {
        if state.changes.contains(.pages) {
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(state.pages)
            dataSource.apply(snapshot) { [weak self] in
                guard let self else { return }
                let indexPath = IndexPath(row: self.viewModel.state.selectedPageIndex, section: 0)
                self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
            }
        }

        if let index = state.loadedThumbnail, index < dataSource.snapshot().itemIdentifiers.count {
            var snapshot = dataSource.snapshot()
            let label = dataSource.snapshot().itemIdentifiers[index]
            snapshot.reloadItems([label])
            dataSource.apply(snapshot)
        }

        if state.changes.contains(.userInterface) {
            var snapshot = dataSource.snapshot()
            snapshot.reloadSections([0])
            dataSource.apply(snapshot)
        }

        if state.changes.contains(.scrollToSelection) {
            let indexPath = IndexPath(row: state.selectedPageIndex, section: 0)
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
        }
    }
}

extension PdfThumbnailsViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let toFetch = indexPaths.map({ $0.row }).map(UInt.init)
        viewModel.process(action: .prefetch(toFetch))
    }
}

extension PdfThumbnailsViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel.process(action: .setSelectedPage(pageIndex: indexPath.row, type: .fromSidebar))
    }
}
